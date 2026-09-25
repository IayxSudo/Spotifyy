#!/usr/bin/env bash
# Local IPA build — mirror of .github/workflows/main.yml. Produces an IPA
# you can sign with Sideloadly/AltStore/TrollStore.
#
# Pipeline:
#   1. Build SpotifyySwiftProtobuf.framework from apple/swift-protobuf source
#      (renamed module — see Tools/SwiftProtobufBuild/).
#   2. theos `make package FINALPACKAGE=1` — produces .deb with
#      Spotifyy.dylib + Spotifyy.bundle + framework.
#   3. Build zxPluginsInject.dylib — sideload compat shim (keychain redirect,
#      group containers, CloudKit stub). LC-injected via ipapatch in step 6.
#   4. clean-base-ipa.py strips any tweak already baked into the base IPA —
#      sideloadable Spotify IPAs are usually pre-patched, and loading Spotifyy
#      on top of one of those runs two copies of the same tweak in one process.
#   5. cyan inject deb-contents (dylib + framework + bundle) into vanilla IPA.
#   6. ipapatch LC-inject zxPluginsInject into main exec + every appex.
#   7. Strip Watch.app if it survived cyan -du.
#   8. primary-icon.sh replaces the default home-screen icon.
#   9. app-label.sh sets the home-screen label to "Spotifyy".
#
# Requires: theos, cyan (pyzule-rw), ipapatch, dpkg, ldid, plutil.

set -euo pipefail

VANILLA_IPA="${1:-}"
[ -n "$VANILLA_IPA" ] && [ -f "$VANILLA_IPA" ] || {
    echo "usage: $0 <path/to/Spotify-vanilla.ipa>" >&2
    exit 1
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

[ -n "${THEOS:-}" ] || { [ -d "$HOME/theos" ] && export THEOS="$HOME/theos" || { echo "THEOS not set"; exit 1; }; }

VERSION=$(grep -E '^Version:' control | awk '{print $2}')
SPOT_VERSION=$(unzip -p "$VANILLA_IPA" 'Payload/Spotify.app/Info.plist' \
    | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || echo "unknown")
OUT_DIR="Outputs/IPAS"
OUT_IPA="$OUT_DIR/Spotifyy-${VERSION}-${SPOT_VERSION}.ipa"
mkdir -p "$OUT_DIR"

color() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }

color "1/9  SpotifyySwiftProtobuf.framework"
chmod +x Tools/SwiftProtobufBuild/build-spotifyyswiftprotobuf.sh
Tools/SwiftProtobufBuild/build-spotifyyswiftprotobuf.sh

color "2/9  theos make package"
THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1
DEB_FILE=$(ls -t packages/com.spotifyy.spotifyy_*.deb 2>/dev/null | head -1)
[ -n "$DEB_FILE" ] || { echo "deb not produced"; exit 1; }

color "3/9  zxPluginsInject.dylib"
chmod +x Tools/build-zxpi.sh
Tools/build-zxpi.sh >/dev/null

color "4/9  extract deb"
DEB_EXTRACT="$REPO_DIR/Outputs/deb-extract"
rm -rf "$DEB_EXTRACT"; mkdir -p "$DEB_EXTRACT"
dpkg-deb -R "$DEB_FILE" "$DEB_EXTRACT"
DYLIB_SRC=$(find "$DEB_EXTRACT" -name 'Spotifyy.dylib' | head -1)
BUNDLE_SRC=$(find "$DEB_EXTRACT" -type d -name 'Spotifyy.bundle' | head -1)
FRAMEWORK_SRC=$(find "$DEB_EXTRACT" -type d -name 'SpotifyySwiftProtobuf.framework' | head -1)
[ -n "$DYLIB_SRC" ] || { echo "dylib not in deb"; exit 1; }

color "5/9  strip pre-baked tweak from base IPA"
# Work on a copy so the IPA the caller handed us is never modified.
CLEAN_IPA="$REPO_DIR/Outputs/base-clean.ipa"
python3 Tools/clean-base-ipa.py "$VANILLA_IPA" -o "$CLEAN_IPA"

color "6/9  cyan inject"
INJECT=("$DYLIB_SRC")
[ -n "$FRAMEWORK_SRC" ] && INJECT+=("$FRAMEWORK_SRC")
[ -n "$BUNDLE_SRC" ]    && INJECT+=("$BUNDLE_SRC")
rm -f "$OUT_IPA"
cyan -i "$CLEAN_IPA" -o "$OUT_IPA" -f "${INJECT[@]}" -c 9 -m 15.0 -du

color "7/9  ipapatch LC-inject zxPluginsInject"
ipapatch --input "$OUT_IPA" --inplace --noconfirm --dylib packages/zxPluginsInject.dylib

# Belt-and-suspenders: cyan -du strips appex/Watch but verify.
cd "$OUT_DIR"
rm -rf Payload
unzip -q "$(basename "$OUT_IPA")"
if [ -d "Payload/Spotify.app/Watch" ]; then
    rm -rf Payload/Spotify.app/Watch
    zip -qry "$(basename "$OUT_IPA")" Payload
fi
rm -rf Payload
cd - >/dev/null

color "8/9  primary app icon"
chmod +x Tools/primary-icon.sh
Tools/primary-icon.sh "$OUT_IPA"

color "9/9  home-screen label"
chmod +x Tools/app-label.sh
Tools/app-label.sh "$OUT_IPA"

color "Done"
ls -lh "$OUT_IPA"
echo "Sign with Sideloadly / AltStore / TrollStore."
