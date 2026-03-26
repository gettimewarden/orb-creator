#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORB="$SCRIPT_DIR/assets/orb.png"

# Defaults
INPUT_DIR="$SCRIPT_DIR/input"
OUTPUT_DIR="$SCRIPT_DIR/output"
SIZE=""
START_NUM=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --size)    SIZE="$2"; shift 2 ;;
        --start)   START_NUM="$2"; shift 2 ;;
        --orb)     ORB="$2"; shift 2 ;;
        --output)  OUTPUT_DIR="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: ./apply-orb.sh [input_dir] [options]"
            echo ""
            echo "Arguments:"
            echo "  input_dir          Source images directory (default: ./input)"
            echo ""
            echo "Options:"
            echo "  --size   N         Output size in pixels (default: orb's native size)"
            echo "  --start  N         Starting file number (default: auto-detect)"
            echo "  --orb    PATH      Path to orb overlay (default: ./assets/orb.png)"
            echo "  --output DIR       Output directory (default: ./output)"
            echo "  -h, --help         Show this help"
            exit 0
            ;;
        *)
            if [ -d "$1" ]; then
                INPUT_DIR="$1"
            else
                echo "Error: Unknown option or directory not found: $1"; exit 1
            fi
            shift
            ;;
    esac
done

# Validate
[ -f "$ORB" ] || { echo "Error: Orb not found at $ORB"; exit 1; }
[ -d "$INPUT_DIR" ] || { echo "Error: Input directory not found: $INPUT_DIR"; exit 1; }
command -v magick >/dev/null || { echo "Error: ImageMagick is required (brew install imagemagick)"; exit 1; }

# Derive size from orb if not specified
if [ -z "$SIZE" ]; then
    SIZE=$(magick identify -format "%w" "$ORB")
fi

# Auto-detect next number from output directory
if [ -z "$START_NUM" ]; then
    START_NUM=$(ls "$OUTPUT_DIR"/*.png 2>/dev/null \
        | xargs -I{} basename {} .png \
        | grep -E '^[0-9]+$' \
        | sort -n | tail -1)
    START_NUM=$(( ${START_NUM:-0} + 1 ))
fi

mkdir -p "$OUTPUT_DIR"

# Prepare orb assets once: resize orb + extract circular mask from alpha channel
ORB_RESIZED=$(mktemp /tmp/orb_XXXXXX.png)
CIRCLE_MASK=$(mktemp /tmp/mask_XXXXXX.png)
trap 'rm -f "$ORB_RESIZED" "$CIRCLE_MASK"' EXIT

magick "$ORB" -resize "${SIZE}x${SIZE}" "$ORB_RESIZED"
magick "$ORB_RESIZED" -alpha extract "$CIRCLE_MASK"

echo "Orb:    $ORB"
echo "Size:   ${SIZE}x${SIZE}"
echo "Input:  $INPUT_DIR"
echo "Output: $OUTPUT_DIR"
echo "Start:  $START_NUM"
echo ""

NUM=$START_NUM
COUNT=0
for img in "$INPUT_DIR"/*; do
    [ -f "$img" ] || continue
    case "${img,,}" in *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.tiff) ;; *) continue ;; esac

    output_name="${NUM}.png"
    echo "$(basename "$img") -> $output_name"

    # Center-crop to square -> resize -> circular mask -> orb overlay (Screen blend)
    magick "$img" \
        -resize "${SIZE}x${SIZE}^" \
        -gravity center -extent "${SIZE}x${SIZE}" \
        \( "$CIRCLE_MASK" \) -alpha off -compose CopyOpacity -composite \
        \( "$ORB_RESIZED" -compose Screen \) -composite \
        "$OUTPUT_DIR/$output_name"

    NUM=$((NUM + 1))
    COUNT=$((COUNT + 1))
done

echo ""
echo "Done! $COUNT images -> $OUTPUT_DIR"
