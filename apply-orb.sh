#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORB="$SCRIPT_DIR/assets/orb.png"

# Defaults
INPUT_DIR="$SCRIPT_DIR/input"
OUTPUT_DIR="$SCRIPT_DIR/output"
SIZE=""
START_NUM=""
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --size)    SIZE="$2"; shift 2 ;;
        --start)   START_NUM="$2"; shift 2 ;;
        --orb)     ORB="$2"; shift 2 ;;
        --output)  OUTPUT_DIR="$2"; shift 2 ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
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
            echo "  -j, --jobs N       Parallel jobs (default: number of CPU cores)"
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

# Get orb canvas size
ORB_SIZE=$(magick identify -format "%w" "$ORB")

# Detect the orb's visible circle within the canvas
CIRCLE_INFO=$(magick "$ORB" -alpha extract -trim -format "%w %X %Y" info:)
CIRCLE_DIM=$(echo "$CIRCLE_INFO" | awk '{print $1}')
CIRCLE_X=$(echo "$CIRCLE_INFO" | awk '{gsub(/\+/,"",$2); print $2}')
CIRCLE_Y=$(echo "$CIRCLE_INFO" | awk '{gsub(/\+/,"",$3); print $3}')

# Apply output scaling if --size is given
if [ -n "$SIZE" ]; then
    SCALE=$(echo "$SIZE $ORB_SIZE" | awk '{printf "%.6f", $1/$2}')
    CIRCLE_DIM=$(echo "$CIRCLE_DIM $SCALE" | awk '{printf "%d", $1*$2}')
    CIRCLE_X=$(echo "$CIRCLE_X $SCALE" | awk '{printf "%d", $1*$2}')
    CIRCLE_Y=$(echo "$CIRCLE_Y $SCALE" | awk '{printf "%d", $1*$2}')
else
    SIZE=$ORB_SIZE
fi

# Auto-detect next number from output directory
if [ -z "$START_NUM" ]; then
    START_NUM=$(ls "$OUTPUT_DIR"/*.png 2>/dev/null \
        | xargs -I{} basename {} .png \
        | grep -E '^[0-9]+$' \
        | sort -n | tail -1)
    START_NUM=$(( ${START_NUM:-0} + 1 ))
fi

# Clean output directory and recreate
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Prepare orb assets once
ORB_RESIZED=$(mktemp /tmp/orb_XXXXXX.png)
CIRCLE_MASK=$(mktemp /tmp/mask_XXXXXX.png)
trap 'rm -f "$ORB_RESIZED" "$CIRCLE_MASK"' EXIT

magick "$ORB" -resize "${SIZE}x${SIZE}" -quality 95 -depth 8 "$ORB_RESIZED"
magick "$ORB_RESIZED" -alpha extract "$CIRCLE_MASK"

echo "Orb:       $ORB (${ORB_SIZE}x${ORB_SIZE})"
echo "Circle:    ${CIRCLE_DIM}x${CIRCLE_DIM} at +${CIRCLE_X}+${CIRCLE_Y}"
echo "Output:    ${SIZE}x${SIZE}"
echo "Input:     $INPUT_DIR"
echo "Output:    $OUTPUT_DIR"
echo "Start:     $START_NUM"
echo "Jobs:      $JOBS"
echo ""

# ── Phase 1: Apply orb (parallel via job pool) ────────────────────────────────

# Collect images into arrays
IMAGES=()
NUMBERS=()
NUM=$START_NUM
for img in "$INPUT_DIR"/*; do
    [ -f "$img" ] || continue
    ext=$(echo "${img##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext" in png|jpg|jpeg|webp|bmp|tiff|tif|avif|heic|gif|svg) ;; *) continue ;; esac
    IMAGES+=("$img")
    NUMBERS+=("$NUM")
    NUM=$((NUM + 1))
done

COUNT=${#IMAGES[@]}
if [ "$COUNT" -eq 0 ]; then
    echo "No images found in $INPUT_DIR"
    exit 0
fi

echo "Phase 1: Applying orb to $COUNT images ($JOBS parallel jobs)..."

RUNNING=0
FAILED=0
for i in $(seq 0 $((COUNT - 1))); do
    img="${IMAGES[$i]}"
    num="${NUMBERS[$i]}"

    (
        # 1. Create transparent canvas at full orb size
        # 2. Resize source image to fill the visible circle (center-crop to square)
        # 3. Place it at the circle's offset on the canvas
        # 4. Apply circular mask from the orb's alpha channel
        # 5. Composite the orb on top using Screen blend mode
        magick \
            \( -size "${SIZE}x${SIZE}" xc:none \) \
            \( "$img" -resize "${CIRCLE_DIM}x${CIRCLE_DIM}^" \
               -gravity center -extent "${CIRCLE_DIM}x${CIRCLE_DIM}" \) \
            -gravity northwest -geometry "+${CIRCLE_X}+${CIRCLE_Y}" -composite \
            \( "$CIRCLE_MASK" \) -compose CopyOpacity -composite \
            \( "$ORB_RESIZED" \) -compose Screen -composite \
            -depth 8 -quality 95 \
            PNG32:"${OUTPUT_DIR}/${num}.png" \
        && echo "  $(basename "$img") -> ${num}.png" \
        || { echo "  FAILED: $(basename "$img")"; exit 1; }
    ) &

    RUNNING=$((RUNNING + 1))
    if [ "$RUNNING" -ge "$JOBS" ]; then
        wait -n 2>/dev/null || wait
        RUNNING=$((RUNNING - 1))
    fi
done
wait

echo ""
echo "Phase 1 complete: $COUNT images rendered"

# ── Phase 2: Compress with pngquant (parallel) ────────────────────────────────

if command -v pngquant >/dev/null; then
    echo ""
    echo "Phase 2: Compressing with pngquant ($JOBS parallel jobs)..."
    ls "$OUTPUT_DIR"/*.png | xargs -P "$JOBS" -I {} pngquant --quality=65-95 --speed 1 --force --ext .png --strip {}
    echo "Phase 2 complete"
else
    echo ""
    echo "Skipping pngquant: not found (brew install pngquant)"
fi

# ── Phase 3: Optimize with clop ────────────────────────────────────────────────

if command -v clop >/dev/null; then
    echo ""
    echo "Phase 3: Optimizing with clop..."
    clop optimise --no-progress --no-adaptive-optimisation --aggressive --types png "$OUTPUT_DIR"
    echo "Phase 3 complete"
else
    echo ""
    echo "Skipping clop: not found (install from https://lowtechguys.com/clop)"
fi

echo ""
echo "Done! $COUNT images -> $OUTPUT_DIR"
