#!/usr/bin/env python3
"""Turn a pre-patched Spotify IPA into a clean base for Spotifyy injection.

Most "decrypted Spotify" IPAs circulating for sideloading already have a tweak
baked in (commonly EeveeSpotify, plus a zxPluginsInject shim). Injecting
Spotifyy.dylib on top of one of those loads *two* copies of essentially the same
tweak into the same process: duplicate hooks, duplicate settings panes,
duplicate player observers. That is a crash, not a feature.

This removes the stale pieces:

  * Payload/<app>/Frameworks/<Tweak>.dylib and any <Tweak>.bundle
  * the matching LC_LOAD_DYLIB entries in every Mach-O in the bundle
  * the tweak's entries in the code-signing manifest (_CodeSignature/CodeResources)
  * its name left in the OpenSpotify Safari extension, including the URL it
    hands pages back with, and its localised description text

That last group matters for more than tidiness: the extension hands a page back
to the app as spotify://<host>/<path> and the tweak decides whether to accept it
by comparing that host, so a base patched by a differently-named tweak sends a
host the injected Spotifyy does not recognise and the handoff does nothing.

Load commands are not deleted (that would mean rewriting the whole Mach-O and
every file offset in it). They are downgraded to LC_LOAD_WEAK_DYLIB instead,
which dyld silently skips when the file is absent -- the same technique the
pre-patched IPAs already use for their own zxPluginsInject shim.

Everything else is copied byte-for-byte, including symlink entries and file
modes, so the result is an ordinary IPA that cyan / ipapatch / Sideloadly can
consume.

The same script also has a second, narrower job. The OpenSpotify Safari
Extension is cloned from a third-party repository and injected *after* this strip,
so the branding it carries can only be cleared once the IPA is finished. That is
what --scrub-only is for: no payload is deleted and no load command is touched,
which it must not be, because by then the bundle holds the Spotifyy.dylib we
just injected and STALE_STEMS would match it.

Usage:
    python3 Tools/clean-base-ipa.py Spotify.ipa             # rewrite in place
    python3 Tools/clean-base-ipa.py -o clean.ipa dirty.ipa
    python3 Tools/clean-base-ipa.py --check dirty.ipa       # report only
    python3 Tools/clean-base-ipa.py --scrub-only built.ipa  # branding only
    python3 Tools/clean-base-ipa.py --scrub-only --check built.ipa
"""

import argparse
import json
import os
import plistlib
import re
import struct
import sys
import zipfile

# Injection basenames to strip, without the extension. A stale Spotifyy.dylib is
# stripped too, so re-running this on an already-patched IPA cleans it.
#
# zxPluginsInject belongs in this list even though it is not a competing tweak:
# ipapatch refuses to LC-inject a dylib whose load command is already present
# ("already exists (already patched)") and aborts the whole build, and a base
# that was patched before always carries one in the main executable and in every
# appex. Repointing that load command also clears ipapatch's name comparison, so
# its own fresh injection succeeds.
STALE_STEMS = ("EeveeSpotify", "Spotifyy", "zxPluginsInject")

# Bundles belonging to those tweaks. Jailbreak tweaks ship no bundle, but
# IPA-patched builds of them do. zxPluginsInject has none.
STALE_BUNDLES = ("EeveeSpotify.bundle", "Spotifyy.bundle")

# A stale load is pointed at a path that cannot exist as well as downgraded to
# LC_LOAD_WEAK_DYLIB, so the skip holds independently of dyld's weak-link
# behaviour.
#
# The replacement is padded to the *exact* length of the path it replaces: a
# shorter string would leave NUL bytes behind, and the load-command injectors
# downstream (cyan, ipapatch) look for exactly that kind of slack to write their
# own commands into. Reclaiming it shifts the table and leaves commands that no
# longer parse.
STRIPPED_SUFFIX = b".dylib"

MACHO_MAGICS = frozenset((
    0xFEEDFACE,  # 32-bit, host endian
    0xFEEDFACF,  # 64-bit, host endian
    0xCEFAEDFE,  # 32-bit, swapped
    0xCFFAEDFE,  # 64-bit, swapped
    0xCAFEBABE,  # fat, big endian
    0xCAFEBABF,  # fat, big endian, 64-bit
    0xBEBAFECA,  # fat, little endian
    0xBFBAFECA,  # fat, little endian, 64-bit
))

LC_REQ_DYLD = 0x80000000
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x18
LC_REEXPORT_DYLIB = 0x1F
LC_LOAD_UPWARD_DYLIB = 0x23

# Command values that introduce a library load (with and without LC_REQ_DYLD).
DYLIB_LOAD_CMDS = frozenset((
    LC_LOAD_DYLIB,
    LC_LOAD_WEAK_DYLIB | LC_REQ_DYLD,
    LC_REEXPORT_DYLIB | LC_REQ_DYLD,
    LC_LOAD_UPWARD_DYLIB | LC_REQ_DYLD,
))

WEAK_LOAD_CMD = LC_LOAD_WEAK_DYLIB | LC_REQ_DYLD


# The upstream tweak's name, where it survives outside the files we delete.
LEGACY_NAME = b"EeveeSpotify"

# Any case-insensitive "eevee", used only to report what is left behind.
LEGACY_ANYWHERE = re.compile(rb"eevee", re.I)

# _CodeSignature/CodeResources lists every file in the bundle, so a base that
# was patched before names the tweak we just deleted.
CODE_SIGN_MANIFEST = "_CodeSignature/CodeResources"

# The OpenSpotify Safari extension hands a page back to the app as
# spotify://<host>/<path>, and our tweak accepts it only when <host> is ours
# (see URL.isOpenSpotifySafariExtension). A base patched by the upstream tweak
# still sends upstream's host, so the handoff is silently ignored there. Point
# it at our host whatever the base shipped.
LEGACY_HANDOFF = re.compile(rb"spotify://[A-Za-z0-9._-]+/")
OUR_HANDOFF = b"spotify://spotifyy/"

# Sentences are split on punctuation followed by whitespace, so a version number
# like "3.1" inside one stays part of that sentence instead of ending it.
SENTENCE_BREAK = re.compile(r"(?<=[.!?])\s+")

# Only these can be rewritten as text without risking a binary payload.
TEXT_SUFFIXES = (".js", ".json", ".html", ".htm")

# Our own placeholder from an earlier run: a path of nothing but underscores.
# Recognising it keeps the tool idempotent and repairs a base that was cleaned
# by an older version, whose shorter replacement left free space in the header.
LEGACY_PLACEHOLDER = re.compile(r"^/_{2,}\.dylib$")


def is_stale_dylib(name):
    base = os.path.basename(name)
    if not base.endswith(".dylib"):
        return False
    if base[: -len(".dylib")] in STALE_STEMS:
        return True
    return bool(LEGACY_PLACEHOLDER.match("/" + base))


def stale_bundle_component(name):
    """Return the stale tweak bundle found in a path, if any."""
    for part in name.split("/"):
        if part in STALE_BUNDLES:
            return part
    return None


def looks_like_macho(data):
    return len(data) >= 4 and struct.unpack_from("<I", data, 0)[0] in MACHO_MAGICS


def scrub_codesign(data):
    """Drop code-signing keys for the payloads we removed.

    The signature is void the moment anything is injected - Sideloadly, AltStore
    and TrollStore all re-sign or bypass it - so removing keys for files that no
    longer exist cannot make the bundle less installable, and it stops the
    manifest from listing the upstream tweak.

    Returns (new bytes, notes).
    """
    try:
        manifest = plistlib.loads(data)
    except Exception:
        return data, []
    if not isinstance(manifest, dict):
        return data, []

    dropped = 0
    for section in ("files", "files2"):
        entries = manifest.get(section)
        if not isinstance(entries, dict):
            continue
        stale_keys = [k for k in entries if is_stale_dylib(k) or stale_bundle_component(k)]
        for key in stale_keys:
            del entries[key]
        dropped += len(stale_keys)

    if not dropped:
        return data, []

    newdata = plistlib.dumps(manifest, fmt=plistlib.FMT_BINARY, sort_keys=False)
    return newdata, ["dropped %d stale key(s) from %s" % (dropped, CODE_SIGN_MANIFEST)]


def scrub_message(message):
    """Drop sentences naming the upstream tweak, rename any other mention.

    The extension's description is "Displays an Open in Spotify alert for
    sideloaded Spotify. Requires EeveeSpotify 3.1 or newer." - the second half is
    a stale version gate, so the sentence goes rather than being reworded.
    """
    kept = [s for s in SENTENCE_BREAK.split(message) if "EeveeSpotify" not in s]
    cleaned = " ".join(kept).strip()
    if not cleaned:
        cleaned = message.replace("EeveeSpotify", "Spotifyy")
    return cleaned


def scrub_text(name, data):
    """Repoint the Safari-extension handoff, rename leftover upstream text.

    Returns (new bytes, notes).
    """
    notes = []
    basename = name.rsplit("/", 1)[-1]

    if basename == "content.js":
        data, count = LEGACY_HANDOFF.subn(OUR_HANDOFF, data)
        if count:
            notes.append("pointed %d OpenSpotify handoff URL(s) at %s"
                         % (count, OUR_HANDOFF.decode()))

    if "/_locales/" in name and basename.endswith(".json"):
        try:
            table = json.loads(data.decode("utf-8"))
        except Exception:
            table = None
        if isinstance(table, dict):
            rewrote = 0
            for entry in table.values():
                if not isinstance(entry, dict):
                    continue
                message = entry.get("message")
                if isinstance(message, str) and "EeveeSpotify" in message:
                    entry["message"] = scrub_message(message)
                    rewrote += 1
            if rewrote:
                data = (json.dumps(table, indent=4, ensure_ascii=False)
                        + "\n").encode("utf-8")
                notes.append("rewrote %d localised extension string(s) in %s"
                             % (rewrote, basename))

    # Anything else that still spells the name out and can safely be treated as
    # text. Mach-O is never rewritten here: a shorter string would move every
    # offset after it, and a load path is already handled by patch_macho.
    if LEGACY_NAME in data and name.endswith(TEXT_SUFFIXES):
        data, count = re.subn(b"EeveeSpotify", b"Spotifyy", data)
        notes.append("renamed %d leftover upstream name(s) in %s" % (count, basename))

    return data, notes


def scrub(name, data):
    """Apply the base-level scrubs that are not Mach-O edits."""
    if name.endswith(CODE_SIGN_MANIFEST):
        return scrub_codesign(data)
    return scrub_text(name, data)


def track_leftovers(name, data, leftovers):
    """Record anything still naming the upstream tweak, for the report."""
    count = len(LEGACY_ANYWHERE.findall(data))
    if count:
        leftovers.append((name, count))


def exact_length_path(room):
    """A path that cannot exist, exactly `room` bytes long (or None if absurd)."""
    if room < len(STRIPPED_SUFFIX) + 2:
        return None
    return b"/" + b"_" * (room - len(STRIPPED_SUFFIX) - 1) + STRIPPED_SUFFIX


def patch_thin(buf, off):
    """Neutralise stale dylib loads in one thin Mach-O slice.

    Returns (matched, rewritten, unrewritten) path lists.
    """
    magic = struct.unpack_from("<I", buf, off)[0]
    if magic == 0xFEEDFACF:
        header = 32
    elif magic == 0xFEEDFACE:
        header = 28
    else:
        return [], [], []

    ncmds = struct.unpack_from("<I", buf, off + 16)[0]
    end = off + header + struct.unpack_from("<I", buf, off + 20)[0]
    o = off + header
    hits = []
    rewritten = []
    unrewritten = []

    for _ in range(ncmds):
        if o + 8 > len(buf) or o + 8 > end:
            break
        cmd, cmdsize = struct.unpack_from("<II", buf, o)
        if cmdsize < 8 or o + cmdsize > len(buf):
            break
        if cmd in DYLIB_LOAD_CMDS and cmdsize > 12:
            str_off = struct.unpack_from("<I", buf, o + 8)[0]
            if 12 <= str_off < cmdsize:
                raw = bytes(buf[o + str_off:o + cmdsize]).split(b"\x00")[0]
                path = raw.decode("utf-8", "replace")
                if is_stale_dylib(path):
                    if cmd != WEAK_LOAD_CMD:
                        struct.pack_into("<I", buf, o, WEAK_LOAD_CMD)
                    region = buf[o + str_off:o + cmdsize]
                    nul = region.find(b"\x00")
                    room = nul if nul >= 0 else len(region)
                    repl = exact_length_path(room)
                    if repl is not None:
                        # Leave the original NUL terminator in place; only the
                        # string bytes change, so the command keeps its size and
                        # no free space is created.
                        buf[o + str_off:o + str_off + len(repl)] = repl
                        rewritten.append(path)
                    else:
                        unrewritten.append(path)
                    hits.append(path)
        o += cmdsize

    return hits, rewritten, unrewritten


def patch_macho(data):
    """Weaken stale dylib loads in a Mach-O (fat or thin).

    Returns (matched paths, new bytes).
    """
    buf = bytearray(data)
    magic = struct.unpack_from("<I", buf, 0)[0]
    matched, rewritten, unrewritten = [], [], []

    if magic in (0xBEBAFECA, 0xBFBAFECA, 0xCAFEBABE, 0xCAFEBABF):
        big = magic in (0xCAFEBABE, 0xCAFEBABF)
        fmt = ">5I" if big else "<5I"
        narch = struct.unpack_from((">I" if big else "<I"), buf, 4)[0]
        if narch > 32:
            return {"matched": [], "rewritten": [], "unrewritten": []}, data
        for i in range(narch):
            _, _, off, _, _ = struct.unpack_from(fmt, buf, 8 + i * 20)
            h, r, u = patch_thin(buf, off)
            matched += h
            rewritten += r
            unrewritten += u
    else:
        matched, rewritten, unrewritten = patch_thin(buf, 0)

    return {"matched": matched, "rewritten": rewritten,
            "unrewritten": unrewritten}, bytes(buf)


def clean(src, dst, scrub_only=False):
    """Copy src to dst, dropping stale tweak payloads. Returns a report dict.

    scrub_only leaves the payload exactly as it is - nothing removed, no load
    command rewritten - and only clears branding, which is what a finished IPA
    can take. It exists because the OpenSpotify appex is injected from a
    third-party repository after the strip: its leftovers can only be cleared
    afterwards, and by then STALE_STEMS would match the Spotifyy.dylib the strip
    is supposed to protect.
    """
    removed = []
    patched = []
    scrubbed = []
    leftovers = []
    copied = 0

    with zipfile.ZipFile(src, "r") as zin:
        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
            for info in zin.infolist():
                name = info.filename

                if not scrub_only and (is_stale_dylib(name) or stale_bundle_component(name)):
                    removed.append(name)
                    continue

                data = zin.read(info)
                copied += 1

                if info.is_dir():
                    pass
                elif looks_like_macho(data):
                    if not scrub_only:
                        res, newdata = patch_macho(data)
                        if res["matched"]:
                            res["file"] = name
                            patched.append(res)
                            data = newdata
                else:
                    newdata, notes = scrub(name, data)
                    scrubbed += ["%s: %s" % (name, note) for note in notes]
                    data = newdata

                if not info.is_dir():
                    track_leftovers(name, data, leftovers)

                # Reuse the original ZipInfo so symlink bits, file modes and
                # timestamps survive the copy. writestr fills in CRC and sizes.
                if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    info.compress_type = zipfile.ZIP_DEFLATED
                zout.writestr(info, data)

    return {"removed": removed, "patched": patched, "scrubbed": scrubbed,
            "leftovers": leftovers, "copied": copied}


def inspect(src, scrub_only=False):
    """Report what a clean would do, without writing anything."""
    removed = []
    patched = []
    scrubbed = []
    leftovers = []
    with zipfile.ZipFile(src, "r") as zin:
        for info in zin.infolist():
            name = info.filename
            if not scrub_only and (is_stale_dylib(name) or stale_bundle_component(name)):
                removed.append(name)
                continue
            if info.is_dir():
                continue
            data = zin.read(info)
            if looks_like_macho(data):
                if not scrub_only:
                    res, newdata = patch_macho(data)
                    if res["matched"]:
                        res["file"] = name
                        patched.append(res)
                        data = newdata
            else:
                newdata, notes = scrub(name, data)
                scrubbed += ["%s: %s" % (name, note) for note in notes]
                data = newdata
            track_leftovers(name, data, leftovers)
    return {"removed": removed, "patched": patched, "scrubbed": scrubbed,
            "leftovers": leftovers, "copied": 0}


def report(res):
    dylibs = [r for r in res["removed"] if is_stale_dylib(r)]
    for r in dylibs:
        print("[clean-base] removing %s" % r)

    for bundle in STALE_BUNDLES:
        n = len([r for r in res["removed"] if bundle in r.split("/")])
        if n:
            print("[clean-base] removing %s (%d entries)" % (bundle, n))

    for entry in res["patched"]:
        for h in entry["matched"]:
            if h in entry["rewritten"]:
                where = exact_length_path(len(h)).decode()
            else:
                where = "weak load only"
            print("[clean-base] neutralised load of %s (-> %s) in %s"
                  % (h, where, entry["file"]))
        for h in entry["unrewritten"]:
            print("[clean-base] warning: could not repoint %s in %s, weakened only"
                  % (h, entry["file"]))

    for note in res["scrubbed"]:
        print("[clean-base] %s" % note)

    leftovers = res.get("leftovers", [])
    for name, count in leftovers:
        print("[clean-base] warning: %s still names the upstream tweak (%d occurrence(s))"
              % (name, count))
    if res["scrubbed"] and not leftovers:
        print("[clean-base] no upstream name left anywhere in the bundle")

    if not dylibs and not res["patched"] and not res["removed"] and not res["scrubbed"]:
        print("[clean-base] nothing to strip - base already clean")

    return bool(dylibs or res["removed"] or res["patched"] or res["scrubbed"])


def main(argv=None):
    ap = argparse.ArgumentParser(description="Strip a previously injected tweak from an IPA.")
    ap.add_argument("ipa", help="IPA to clean")
    ap.add_argument("-o", "--output", help="write here instead of in place")
    ap.add_argument("--check", action="store_true",
                    help="report what would be stripped, write nothing")
    ap.add_argument("--scrub-only", action="store_true",
                    help="clear leftover upstream branding only: no payload is "
                         "removed and no load command is rewritten, so this is "
                         "safe to run over a finished IPA")
    args = ap.parse_args(argv)

    src = args.ipa
    if not os.path.isfile(src):
        sys.stderr.write("[clean-base] no such file: %s\n" % src)
        return 1

    if args.check:
        found = report(inspect(src, scrub_only=args.scrub_only))
        print("[clean-base] check only, nothing written")
        return 0 if found else 0

    dst = args.output or (src + ".cleaned")
    res = clean(src, dst, scrub_only=args.scrub_only)
    report(res)

    if not args.output:
        os.replace(dst, src)
        target = src
    else:
        target = dst

    with zipfile.ZipFile(target, "r") as zf:
        bad = zf.testzip()
        n_entries = len(zf.namelist())
    if bad is not None:
        sys.stderr.write("[clean-base] output archive is corrupt at %s\n" % bad)
        return 1

    print("[clean-base] wrote %s (%d entries, %.1f MB)"
          % (target, n_entries, os.path.getsize(target) / 1048576.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
