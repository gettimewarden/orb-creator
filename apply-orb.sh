#!/bin/bash
set -e

# ── Colors & Symbols ──────────────────────────────────────────────────────────

if [ -t 1 ]; then
    BOLD=$'\033[1m'    DIM=$'\033[2m'     RESET=$'\033[0m'
    RED=$'\033[1;31m'  GREEN=$'\033[1;32m' YELLOW=$'\033[1;33m'
    BLUE=$'\033[1;34m' MAGENTA=$'\033[1;35m' CYAN=$'\033[1;36m'
    WHITE=$'\033[1;37m'
else
    BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE=""
fi

CHECK="${GREEN}✓${RESET}"
CROSS="${RED}✗${RESET}"
ARROW="${CYAN}→${RESET}"
DOT="${DIM}·${RESET}"
ORB_SYM="${MAGENTA}◉${RESET}"

header()  { echo ""; echo "${BOLD}${BLUE}━━━ $1 ━━━${RESET}"; echo ""; }
info()    { echo "  ${DIM}$1${RESET}  $2"; }
phase()   { echo ""; echo "${BOLD}${MAGENTA}▸ Phase $1:${RESET} $2"; }
ok()      { echo "  ${CHECK} $1"; }
fail()    { echo "  ${CROSS} ${RED}$1${RESET}"; }
warn()    { echo "  ${YELLOW}⚠${RESET}  $1"; }

show_logo() {
    echo "${BOLD}${MAGENTA}"
    cat << 'LOGO'
   ___       _       ___                _
  / _ \ _ __| |__   / __\ __ ___  __ _| |_ ___  _ __
 | | | | '__| '_ \ / / | '__/ _ \/ _` | __/ _ \| '__|
 | |_| | |  | |_) / /__| | |  __| (_| | || (_) | |
  \___/|_|  |_.__/\____/_|  \___|\__,_|\__\___/|_|
LOGO
    echo "${RESET}"
}

# ── Setup ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORB="$SCRIPT_DIR/assets/orb.png"

INPUT_DIR="$SCRIPT_DIR/input"
OUTPUT_DIR="$SCRIPT_DIR/output"
SIZE=""
START_NUM=""
JOBS=20

# ── Parse Arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --size)    SIZE="$2"; shift 2 ;;
        --start)   START_NUM="$2"; shift 2 ;;
        --orb)     ORB="$2"; shift 2 ;;
        --output)  OUTPUT_DIR="$2"; shift 2 ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
        --help|-h)
            show_logo
            echo "${BOLD}Usage:${RESET} ./apply-orb.sh ${DIM}[input_dir] [options]${RESET}"
            echo ""
            echo "${BOLD}Arguments:${RESET}"
            echo "  ${CYAN}input_dir${RESET}          Source images directory ${DIM}(default: ./input)${RESET}"
            echo ""
            echo "${BOLD}Options:${RESET}"
            echo "  ${CYAN}--size${RESET}   N         Output size in pixels ${DIM}(default: orb's native size)${RESET}"
            echo "  ${CYAN}--start${RESET}  N         Starting file number ${DIM}(default: auto-detect)${RESET}"
            echo "  ${CYAN}--orb${RESET}    PATH      Path to orb overlay ${DIM}(default: ./assets/orb.png)${RESET}"
            echo "  ${CYAN}--output${RESET} DIR       Output directory ${DIM}(default: ./output)${RESET}"
            echo "  ${CYAN}-j, --jobs${RESET} N       Parallel jobs ${DIM}(default: CPU cores)${RESET}"
            echo "  ${CYAN}-h, --help${RESET}         Show this help"
            exit 0
            ;;
        *)
            if [ -d "$1" ]; then
                INPUT_DIR="$1"
            else
                fail "Unknown option or directory not found: $1"; exit 1
            fi
            shift
            ;;
    esac
done

# ── Banner ────────────────────────────────────────────────────────────────────

show_logo

# ── Validate ──────────────────────────────────────────────────────────────────

MISSING=0
[ ! -f "$ORB" ]                    && fail "Orb not found at $ORB"          && MISSING=1
[ ! -d "$INPUT_DIR" ]              && fail "Input dir not found: $INPUT_DIR" && MISSING=1
! command -v magick >/dev/null     && fail "ImageMagick required ${DIM}(brew install imagemagick)${RESET}" && MISSING=1
[ "$MISSING" -eq 1 ] && exit 1

# ── Detect Orb Geometry ──────────────────────────────────────────────────────

ORB_NATIVE=$(magick identify -format "%w" "$ORB")

CIRCLE_INFO=$(magick "$ORB" -alpha extract -trim -format "%w %X %Y" info:)
CIRCLE_DIM=$(echo "$CIRCLE_INFO" | awk '{print $1}')
CIRCLE_X=$(echo "$CIRCLE_INFO" | awk '{gsub(/\+/,"",$2); print $2}')
CIRCLE_Y=$(echo "$CIRCLE_INFO" | awk '{gsub(/\+/,"",$3); print $3}')

SIZE="${SIZE:-231}"
SCALE=$(echo "$SIZE $ORB_NATIVE" | awk '{printf "%.6f", $1/$2}')
CIRCLE_DIM=$(echo "$CIRCLE_DIM $SCALE" | awk '{printf "%d", $1*$2}')
CIRCLE_X=$(echo "$CIRCLE_X $SCALE" | awk '{printf "%d", $1*$2}')
CIRCLE_Y=$(echo "$CIRCLE_Y $SCALE" | awk '{printf "%d", $1*$2}')

# Default to 1 since output is always cleaned
if [ -z "$START_NUM" ]; then
    START_NUM=1
fi

# ── Config Summary ────────────────────────────────────────────────────────────

header "Configuration"
info "${ORB_SYM} Orb"   "${WHITE}${ORB_NATIVE}x${ORB_NATIVE}${RESET}  ${DIM}$(basename "$ORB")${RESET}"
info "  Circle"          "${CYAN}${CIRCLE_DIM}x${CIRCLE_DIM}${RESET} at +${CIRCLE_X}+${CIRCLE_Y}"
info "  Output"          "${GREEN}${SIZE}x${SIZE}${RESET} px"
info "  Input"           "${DIM}${INPUT_DIR}${RESET}"
info "  Output"          "${DIM}${OUTPUT_DIR}${RESET}"
info "  Start #"         "${WHITE}${START_NUM}${RESET}"
info "  Jobs"            "${YELLOW}${JOBS}${RESET} parallel"
echo ""
info "  Tools" ""
command -v magick >/dev/null   && ok "ImageMagick ${DIM}$(magick --version 2>/dev/null | head -1 | awk '{print $3}')${RESET}" || fail "ImageMagick"
command -v pngquant >/dev/null && ok "pngquant ${DIM}$(pngquant --version 2>/dev/null)${RESET}"    || warn "pngquant not found ${DIM}(brew install pngquant)${RESET}"
command -v clop >/dev/null     && ok "clop"                                                         || warn "clop not found ${DIM}(lowtechguys.com/clop)${RESET}"

# ── Clean & Prepare ──────────────────────────────────────────────────────────

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

TMPDIR_ORB=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ORB"' EXIT

ORB_RESIZED="$TMPDIR_ORB/orb.png"
CIRCLE_MASK="$TMPDIR_ORB/mask.png"

magick "$ORB" -resize "${SIZE}x${SIZE}" -quality 95 -depth 8 "$ORB_RESIZED"
magick "$ORB_RESIZED" -alpha extract "$CIRCLE_MASK"

# ── Collect Images ────────────────────────────────────────────────────────────

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
    warn "No images found in $INPUT_DIR"
    exit 0
fi

# ── Phase 1: Apply Orb ───────────────────────────────────────────────────────

phase "1" "Applying orb to ${WHITE}${COUNT}${RESET} images ${DIM}(${JOBS} threads)${RESET}"

RUNNING=0
for i in $(seq 0 $((COUNT - 1))); do
    img="${IMAGES[$i]}"
    num="${NUMBERS[$i]}"

    (
        magick \
            \( -size "${SIZE}x${SIZE}" xc:none \) \
            \( "$img" -resize "${CIRCLE_DIM}x${CIRCLE_DIM}^" \
               -gravity center -extent "${CIRCLE_DIM}x${CIRCLE_DIM}" \) \
            -gravity northwest -geometry "+${CIRCLE_X}+${CIRCLE_Y}" -composite \
            \( "$CIRCLE_MASK" \) -compose CopyOpacity -composite \
            \( "$ORB_RESIZED" \) -compose Screen -composite \
            -strip -depth 8 -quality 95 \
            PNG32:"${OUTPUT_DIR}/${num}.png" \
        && echo "  ${CHECK} ${DIM}$(basename "$img" | cut -c1-45)${RESET}  ${ARROW}  ${GREEN}${num}.png${RESET}" \
        || echo "  ${CROSS} ${RED}$(basename "$img" | cut -c1-45)${RESET}  FAILED"
    ) &

    RUNNING=$((RUNNING + 1))
    if [ "$RUNNING" -ge "$JOBS" ]; then
        wait -n 2>/dev/null || wait
        RUNNING=$((RUNNING - 1))
    fi
done
wait

ok "Rendered ${WHITE}${COUNT}${RESET} images"

# ── Summary ───────────────────────────────────────────────────────────────────

TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" | awk '{print $1}')
MAX_FILE=$(stat -f '%z %N' "$OUTPUT_DIR"/*.png | sort -rn | head -1)
MAX_KB=$(echo "$MAX_FILE" | awk '{printf "%.1f", $1/1024}')
MAX_NAME=$(basename "$(echo "$MAX_FILE" | cut -d' ' -f2-)")
MIN_FILE=$(stat -f '%z %N' "$OUTPUT_DIR"/*.png | sort -n | head -1)
MIN_KB=$(echo "$MIN_FILE" | awk '{printf "%.1f", $1/1024}')

header "Complete"
echo "  ${ORB_SYM} ${WHITE}${COUNT}${RESET} images ${ARROW} ${GREEN}${OUTPUT_DIR}${RESET}"
echo "  ${DOT} Total:      ${CYAN}${TOTAL_SIZE}${RESET}"
echo "  ${DOT} Range:      ${CYAN}${MIN_KB}KB${RESET} – ${CYAN}${MAX_KB}KB${RESET}"
echo "  ${DOT} Largest:    ${CYAN}${MAX_KB}KB${RESET} ${DIM}(${MAX_NAME})${RESET}"
echo "  ${DOT} Dimensions: ${CYAN}${SIZE}x${SIZE}${RESET} px"
echo ""
