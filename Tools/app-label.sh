#!/usr/bin/env bash
# Set the home-screen app label to "Spotifyy" (CFBundleDisplayName/CFBundleName).
#   app-label.sh <Spotify.app>  # patch app dir in place
#   app-label.sh <path.ipa>     # patch ipa in place
#
# Called by the IPA build script and workflows after cyan/ipapatch so the
# sideloaded app shows "Spotifyy" on the home screen instead of "Spotify".

set -euo pipefail

LABEL="Spotifyy"
PB=/usr/libexec/PlistBuddy

patch_app() {
    local app="$1" plist="$1/Info.plist"
    [ -f "$plist" ] || { echo "[app-label] no Info.plist in $app" >&2; return 1; }

    "$PB" -c "Set :CFBundleDisplayName $LABEL" "$plist" 2>/dev/null \
        || "$PB" -c "Add :CFBundleDisplayName string $LABEL" "$plist"
    "$PB" -c "Set :CFBundleName $LABEL" "$plist" 2>/dev/null \
        || "$PB" -c "Add :CFBundleName string $LABEL" "$plist"

    # iPad key only exists on some builds; add it for consistency.
    if "$PB" -c "Print :CFBundleDisplayName~ipad" "$plist" >/dev/null 2>&1; then
        "$PB" -c "Set :CFBundleDisplayName~ipad $LABEL" "$plist"
    fi

    echo "[app-label] set home-screen label to '$LABEL' in $(basename "$app")"
}

patch_ipa() {
    local ipa abs tmp app
    ipa="$1"
    abs="$(cd "$(dirname "$ipa")" && pwd)/$(basename "$ipa")"
    tmp="$(mktemp -d -t app-label.XXXXXX)"
    trap 'rm -rf "$tmp"' RETURN
    ( cd "$tmp" && unzip -q "$abs" )
    app=$(find "$tmp/Payload" -maxdepth 2 -name '*.app' -type d | head -1)
    [ -n "$app" ] || { echo "[app-label] no .app in $ipa" >&2; return 1; }
    patch_app "$app"
    rm -f "$abs"
    ( cd "$tmp" && zip -qry "$abs" Payload )
}

target="${1:-}"
[ -n "$target" ] || { echo "usage: $0 <Spotify.app | app.ipa>" >&2; exit 1; }

if   [ -d "$target" ];                       then patch_app "$target"
elif [ -f "$target" ] && [[ "$target" == *.ipa || "$target" == *.zip ]]; then patch_ipa "$target"
else echo "[app-label] bad target: $target" >&2; exit 1
fi
