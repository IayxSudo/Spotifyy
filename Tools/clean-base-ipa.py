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

Load commands are not deleted (that would mean rewriting the whole Mach-O and
every file offset in it). They are downgraded to LC_LOAD_WEAK_DYLIB instead,
which dyld silently skips when the file is absent -- the same technique the
pre-patched IPAs already use for their own zxPluginsInject shim.

Everything else is copied byte-for-byte, including symlink entries and file
modes, so the result is an ordinary IPA that cyan / ipapatch / Sideloadly can
consume.

Usage:
    python3 Tools/clean-base-ipa.py Spotify.ipa             # rewrite in place
    python3 Tools/clean-base-ipa.py -o clean.ipa dirty.ipa
    python3 Tools/clean-base-ipa.py --check dirty.ipa       # report only
"""

import argparse
import os
import struct
import sys
import zipfile

# Tweak basenames to strip, without the extension. A stale Spotifyy.dylib is
# stripped too, so re-running this on an already-patched IPA cleans it.
#
# zxPluginsInject is deliberately absent: it is not a competing tweak but the
# load-command injector that our own pipeline adds back at the same path, so
# leaving the existing copy in place is harmless and keeps plugin injection
# working even if ipapatch decides the binary is already patched.
STALE_STEMS = ("EeveeSpotify", "Spotifyy")

# Bundles belonging to those tweaks. Jailbreak tweaks ship no bundle, but
# IPA-patched builds of them do.
STALE_BUNDLES = ("EeveeSpotify.bundle", "Spotifyy.bundle")

# A stale load is pointed at a path that cannot exist as well as downgraded to
# LC_LOAD_WEAK_DYLIB, so the skip holds independently of dyld's weak-link
# behaviour. The string is rewritten in place, so it must be no longer than the
# shortest load path we target: "@rpath/Spotifyy.dylib" (21 bytes) has 20 bytes
# of string plus its NUL terminator.
STRIPPED_PATH = b"/__stripped__.dylib"

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


def is_stale_dylib(name):
    base = os.path.basename(name)
    return base.endswith(".dylib") and base[: -len(".dylib")] in STALE_STEMS


def stale_bundle_component(name):
    """Return the stale tweak bundle found in a path, if any."""
    for part in name.split("/"):
        if part in STALE_BUNDLES:
            return part
    return None


def looks_like_macho(data):
    return len(data) >= 4 and struct.unpack_from("<I", data, 0)[0] in MACHO_MAGICS


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
                    if len(STRIPPED_PATH) <= room:
                        pad = b"\x00" * (room - len(STRIPPED_PATH))
                        buf[o + str_off:o + str_off + room] = STRIPPED_PATH + pad
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


def clean(src, dst):
    """Copy src to dst, dropping stale tweak payloads. Returns a report dict."""
    removed = []
    patched = []
    copied = 0

    with zipfile.ZipFile(src, "r") as zin:
        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
            for info in zin.infolist():
                name = info.filename

                if is_stale_dylib(name) or stale_bundle_component(name):
                    removed.append(name)
                    continue

                data = zin.read(info)
                copied += 1

                if not info.is_dir() and looks_like_macho(data):
                    res, newdata = patch_macho(data)
                    if res["matched"]:
                        res["file"] = name
                        patched.append(res)
                        data = newdata

                # Reuse the original ZipInfo so symlink bits, file modes and
                # timestamps survive the copy. writestr fills in CRC and sizes.
                if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    info.compress_type = zipfile.ZIP_DEFLATED
                zout.writestr(info, data)

    return {"removed": removed, "patched": patched, "copied": copied}


def inspect(src):
    """Report what a clean would do, without writing anything."""
    removed = []
    patched = []
    with zipfile.ZipFile(src, "r") as zin:
        for info in zin.infolist():
            name = info.filename
            if is_stale_dylib(name) or stale_bundle_component(name):
                removed.append(name)
                continue
            if info.is_dir():
                continue
            data = zin.read(info)
            if looks_like_macho(data):
                res, _ = patch_macho(data)
                if res["matched"]:
                    res["file"] = name
                    patched.append(res)
    return {"removed": removed, "patched": patched, "copied": 0}


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
            where = STRIPPED_PATH.decode() if h in entry["rewritten"] else "weak load only"
            print("[clean-base] neutralised load of %s (-> %s) in %s"
                  % (h, where, entry["file"]))
        for h in entry["unrewritten"]:
            print("[clean-base] warning: load path %s in %s was longer than %d bytes, "
                  "weakened without repointing"
                  % (h, entry["file"], len(STRIPPED_PATH)))

    if not dylibs and not res["patched"] and not res["removed"]:
        print("[clean-base] nothing to strip - base already clean")

    return bool(dylibs or res["removed"] or res["patched"])


def main(argv=None):
    ap = argparse.ArgumentParser(description="Strip a previously injected tweak from an IPA.")
    ap.add_argument("ipa", help="IPA to clean")
    ap.add_argument("-o", "--output", help="write here instead of in place")
    ap.add_argument("--check", action="store_true",
                    help="report what would be stripped, write nothing")
    args = ap.parse_args(argv)

    src = args.ipa
    if not os.path.isfile(src):
        sys.stderr.write("[clean-base] no such file: %s\n" % src)
        return 1

    if args.check:
        found = report(inspect(src))
        print("[clean-base] check only, nothing written")
        return 0 if found else 0

    dst = args.output or (src + ".cleaned")
    res = clean(src, dst)
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
