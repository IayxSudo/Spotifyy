#!/usr/bin/env bash
# primary-icon.sh — replace the app's PRIMARY (default) icon.
#
# alt-icons.sh only registers *alternate* icons: iOS keeps drawing the stock
# Spotify icon in the default state until the user picks one of the alternates
# by hand. This script changes what the default state looks like.
#
#   alt-icons.sh    -> CFBundleIcons:CFBundleAlternateIcons   (user-pickable)
#   primary-icon.sh -> CFBundleIcons:CFBundlePrimaryIcon      (the real icon)
#
# Three things have to line up for the default icon to actually change:
#
#   1. Every loose AppIcon*.png already sitting in the .app is re-rendered
#      from the chosen source at the exact pixel size its own filename
#      encodes (AppIcon60x60@2x.png -> 120px, AppIcon60x60@3x.png -> 180px,
#      AppIcon83.5x83.5@2x.png -> 167px, ...). That way the sizes iOS already
#      expects keep matching instead of us guessing the icon set.
#   2. Any slot missing from the standard iPhone/iPad set is created too. Builds
#      that ship a couple of loose icons — or none at all, keeping them inside
#      Assets.car — would otherwise end up with a CFBundleIconFiles entry that
#      has no matching file (a @3x device asking for AppIcon60x60@3x.png when
#      only @2x exists), and iOS then falls back to the icon it can find, which
#      is the stock one.
#   3. CFBundleIconName is removed from CFBundlePrimaryIcon and
#      CFBundleIconFiles is repointed at the loose files. While that
#      asset-catalog key is present iOS reads the icon from Assets.car and
#      ignores the loose PNGs entirely, which is why editing the PNGs alone
#      appears to do nothing on modern builds.
#
# Usage:
#   primary-icon.sh                      # only (re)build Assets/AppIcon/primary/
#   primary-icon.sh <Spotify.app> [name]
#   primary-icon.sh <path.ipa>   [name]
#
# [name] is a stem under Assets/AppIcon/sources, or any path to a PNG.
# Defaults to SpotifyyMidnight. Requires sips (macOS).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/Assets/AppIcon/sources"
GENERATED_DIR="$ROOT_DIR/Assets/AppIcon/primary"
PB="${PLIST_BUDDY:-/usr/libexec/PlistBuddy}"
DEFAULT_ICON="SpotifyyMidnight"

# The standard iPhone/iPad icon slots, always guaranteed to exist.
# name:points:scales — points is the icon's nominal size, scales are the
# @Nx variants iOS looks for.
STANDARD_ICONS=(
    "AppIcon20x20:20:2,3"
    "AppIcon29x29:29:2,3"
    "AppIcon40x40:40:2,3"
    "AppIcon60x60:60:2,3"
    "AppIcon76x76~ipad:76:1,2"
    "AppIcon83.5x83.5~ipad:83.5:2"
)

resolve_source() {
    local name="$1"
    if [ -f "$name" ]; then printf '%s\n' "$name"; return 0; fi
    for ext in png PNG jpg jpeg; do
        if [ -f "$SRC_DIR/$name.$ext" ]; then
            printf '%s\n' "$SRC_DIR/$name.$ext"; return 0
        fi
    done
    return 1
}

require_sips() {
    command -v sips >/dev/null 2>&1 || {
        echo "[primary-icon] sips not found — this step needs macOS" >&2
        exit 1
    }
}

# Pixel size encoded by an icon filename, e.g. AppIcon83.5x83.5@2x.png -> 167.
# Prints nothing when the name carries no size (caller then uses the fallback).
size_for_filename() {
    local base="${1%.png}"
    local scale=1
    # iOS puts the idiom marker last: AppIcon60x60@2x~ipad.png — strip that
    # before looking for the scale, or @2x~ipad reads as a 1x icon.
    base="${base%~ipad}"
    base="${base%~iphone}"
    case "$base" in
        *@2x) scale=2; base="${base%@2x}" ;;
        *@3x) scale=3; base="${base%@3x}" ;;
        *@1x) scale=1; base="${base%@1x}" ;;
    esac
    [ -n "${base#AppIcon}" ] || return 1
    local points="${base#AppIcon}"
    case "$points" in
        *x*) points="${points%%x*}" ;;
        *) return 1 ;;
    esac
    # 83.5 x 2 = 167 — awk because bash has no float arithmetic.
    awk -v p="$points" -v s="$scale" 'BEGIN { printf "%d", p * s + 0.5 }'
}

# Apple-style plist stem: scale markers dropped, because iOS appends @2x/@3x
# (and ~ipad) itself when resolving CFBundleIconFiles entries.
plist_stem() {
    local base="${1%.png}"
    base="${base%~ipad}"; base="${base%~iphone}"
    base="${base%@2x}"; base="${base%@3x}"; base="${base%@1x}"
    printf '%s\n' "$base"
}

# All loose icon PNGs in the app bundle, split the way iOS splits them.
loose_icons() {
    local app="$1" want_ipad="$2" f name
    for f in "$app"/AppIcon*.png; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        case "$name" in
            *~ipad.png)
                if [ "$want_ipad" = "yes" ]; then printf '%s\n' "$name"; fi
                ;;
            *)
                if [ "$want_ipad" = "no" ]; then printf '%s\n' "$name"; fi
                ;;
        esac
    done
}

render() {
    local source="$1" out="$2" px="$3"
    sips -s format png -z "$px" "$px" "$source" --out "$out" >/dev/null
}

patch_app() {
    local app="$1" source="$2"
    local plist="$app/Info.plist"
    [ -f "$plist" ] || { echo "[primary-icon] no Info.plist in $app" >&2; return 1; }

    local phone_files ipad_files
    phone_files="$(loose_icons "$app" no)"
    ipad_files="$(loose_icons "$app" yes)"

    # 1 + 2. Re-render (or create) the loose PNGs at their real sizes.
    local rendered=0 name px
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        px="$(size_for_filename "$name")" || continue
        [ "$px" -gt 0 ] || continue
        render "$source" "$app/$name" "$px"
        rendered=$((rendered + 1))
    done <<<"$phone_files"

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        px="$(size_for_filename "$name")" || continue
        [ "$px" -gt 0 ] || continue
        render "$source" "$app/$name" "$px"
        rendered=$((rendered + 1))
    done <<<"$ipad_files"

    # Whatever the bundle did not ship, create. Anything already on disk was
    # re-rendered above, so this only fills the gaps.
    local spec base points scales scale created=0
    for spec in "${STANDARD_ICONS[@]}"; do
        base="${spec%%:*}"; spec="${spec#*:}"
        points="${spec%%:*}"; scales="${spec#*:}"
        IFS=',' read -ra scale_list <<<"$scales"
        for scale in "${scale_list[@]}"; do
            name="$base"
            # iOS expects the scale *before* the idiom marker:
            # AppIcon76x76@2x~ipad.png, never AppIcon76x76~ipad@2x.png.
            if [ "$scale" != "1" ]; then
                case "$name" in
                    *~ipad) name="${name%~ipad}@${scale}x~ipad" ;;
                    *)      name="$name@${scale}x" ;;
                esac
            fi
            [ -f "$app/$name.png" ] && continue
            px="$(awk -v p="$points" -v s="$scale" 'BEGIN { printf "%d", p * s + 0.5 }')"
            render "$source" "$app/$name.png" "$px"
            rendered=$((rendered + 1))
            created=$((created + 1))
        done
    done
    [ "$created" -gt 0 ] && echo "[primary-icon] created $created missing size(s) from the standard set"

    # Re-scan so the plist lists every icon that now exists, including the ones
    # just added, rather than only what the source build happened to ship.
    phone_files="$(loose_icons "$app" no)"
    ipad_files="$(loose_icons "$app" yes)"

    # 3. Drop the asset-catalog icon reference and repoint CFBundleIconFiles.

    # Apple-style stems (scale and idiom markers stripped), de-duplicated but
    # order-preserving: iOS appends @2x/@3x and ~ipad itself, so listing both
    # scales of one slot would just be a duplicate plist entry.
    stems_for() {
        local stem
        while IFS= read -r stem; do
            [ -n "$stem" ] || continue
            plist_stem "$stem"
        done <<<"$1" | awk '!seen[$0]++'
    }

    write_array() {
        local key="$1" stems="$2" index=0 stem
        "$PB" -c "Delete :$key" "$plist" 2>/dev/null || true
        "$PB" -c "Add :$key array" "$plist"
        while IFS= read -r stem; do
            [ -n "$stem" ] || continue
            "$PB" -c "Add :$key:$index string $stem" "$plist"
            index=$((index + 1))
        done <<<"$stems"
    }

    point_icon_files() {
        local base="$1" stems="$2"
        [ -n "$stems" ] || return 0
        # CFBundleIconName wins over the loose files: while it is present iOS
        # reads the icon out of Assets.car and ignores everything rendered above.
        "$PB" -c "Delete :${base}:CFBundlePrimaryIcon:CFBundleIconName" "$plist" 2>/dev/null || true
        write_array "${base}:CFBundlePrimaryIcon:CFBundleIconFiles" "$stems"
    }

    local phone_stems ipad_stems
    phone_stems="$(stems_for "$phone_files")"
    ipad_stems="$(stems_for "$ipad_files")"

    point_icon_files "CFBundleIcons" "$phone_stems"
    if "$PB" -c "Print :CFBundleIcons~ipad" "$plist" >/dev/null 2>&1; then
        point_icon_files "CFBundleIcons~ipad" "$ipad_stems"
    fi

    # Legacy (pre-iOS 5) keys; some iOS versions still consult these on iPad.
    if "$PB" -c "Print :CFBundleIconFiles" "$plist" >/dev/null 2>&1; then
        write_array "CFBundleIconFiles" "$phone_stems"
    fi
    if "$PB" -c "Print :CFBundleIconFiles~ipad" "$plist" >/dev/null 2>&1; then
        write_array "CFBundleIconFiles~ipad" "$ipad_stems"
    fi

    echo "[primary-icon] re-rendered $rendered icon file(s) in $(basename "$app")"
}

patch_ipa() {
    local ipa="$1" source="$2"
    local abs tmp app
    abs="$(cd "$(dirname "$ipa")" && pwd)/$(basename "$ipa")"
    tmp="$(mktemp -d -t primary-icon.XXXXXX)"
    trap 'rm -rf "$tmp"' RETURN
    ( cd "$tmp" && unzip -q "$abs" )
    app=$(find "$tmp/Payload" -maxdepth 2 -name '*.app' -type d | head -1)
    [ -n "$app" ] || { echo "[primary-icon] no .app in $ipa" >&2; return 1; }
    patch_app "$app" "$source"
    rm -f "$abs"
    ( cd "$tmp" && zip -qry "$abs" Payload )
}

target="${1:-}"
name="${2:-$DEFAULT_ICON}"

require_sips
source="$(resolve_source "$name")" || {
    echo "[primary-icon] no icon source named '$name' in $SRC_DIR" >&2
    exit 1
}

# Always keep a rendered copy in Assets/AppIcon/primary/ so the icon is
# reviewable — and reusable by other tooling — without rebuilding an IPA.
mkdir -p "$GENERATED_DIR"
render "$source" "$GENERATED_DIR/Icon-1024.png" 1024

[ -n "$target" ] || { echo "[primary-icon] source $name -> $GENERATED_DIR"; exit 0; }

if   [ -d "$target" ];                       then patch_app "$target" "$source"
elif [ -f "$target" ] && [[ "$target" == *.ipa || "$target" == *.zip ]]; then patch_ipa "$target" "$source"
else echo "[primary-icon] bad target: $target" >&2; exit 1
fi
