#!/usr/bin/env bash
#
# 105k_screen_dataset_downloader
#
# Downloads the 105k Library Screen dataset (~12 TB, 325 parts) from Azure Blob Storage.
# Each part consists of a .zip data file, a .zip.filelist, and a .zip.sha256 checksum file.
#
# Usage:
#   ./105k_screen_dataset_downloader -o /path/to/output [OPTIONS]
#
# Options:
#   -o, --output-dir DIR    Download destination (required)
#   -p, --parts-file FILE   File containing .zip URLs, one per line
#                            (default: 105k_screen_measurements_urls.txt next to this script)
#   -j, --parallel N        Number of parallel downloads (default: 1)
#   -s, --skip-verify       Skip SHA-256 verification after download
#   -r, --range START,END   Download only parts in the given 1-indexed range (e.g. 1,50)
#   -n, --dry-run           Print what would be downloaded without actually downloading
#   -h, --help              Show this help message
#
set -euo pipefail
# ─── Defaults ────────────────────────────────────────────────────────────────
OUTPUT_DIR=""
PARTS_FILE=""
PARALLEL_JOBS=1
SKIP_VERIFY=0
DRY_RUN=0
RANGE_START=""
RANGE_END=""
RETRY_COUNT=5
RETRY_DELAY=10
# ─── Logging ─────────────────────────────────────────────────────────────────
log_info()  { printf "[INFO]  %s\n" "$*"; }
log_ok()    { printf "[OK]    %s\n" "$*"; }
log_warn()  { printf "[WARN]  %s\n" "$*" >&2; }
log_error() { printf "[ERROR] %s\n" "$*" >&2; }
# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage:
  ./105k_screen_dataset_downloader -o /path/to/output [OPTIONS]
Options:
  -o, --output-dir DIR    Download destination (required)
  -p, --parts-file FILE   File containing .zip URLs, one per line
                           (default: 105k_screen_measurements_urls.txt next to this script)
  -j, --parallel N        Number of parallel downloads (default: 1)
  -s, --skip-verify       Skip SHA-256 verification after download
  -r, --range START,END   Download only parts in the given 1-indexed range (e.g. 1,50)
  -n, --dry-run           Print what would be downloaded without actually downloading
  -h, --help              Show this help message
EOF
    exit 0
}
# ─── Parse arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
        -p|--parts-file)  PARTS_FILE="$2"; shift 2 ;;
        -j|--parallel)    PARALLEL_JOBS="$2"; shift 2 ;;
        -s|--skip-verify) SKIP_VERIFY=1; shift ;;
        -r|--range)
            RANGE_START="$(echo "$2" | cut -d, -f1)"
            RANGE_END="$(echo "$2"   | cut -d, -f2)"
            shift 2
            ;;
        -n|--dry-run)     DRY_RUN=1; shift ;;
        -h|--help)        usage ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done
# ─── Validate output directory ────────────────────────────────────────────────
if [[ -z "$OUTPUT_DIR" ]]; then
    log_error "Output directory is required. Specify it with -o/--output-dir."
    echo ""
    usage
fi
# ─── Dependency checks ───────────────────────────────────────────────────────
DOWNLOAD_CMD=""
if command -v curl &>/dev/null; then
    DOWNLOAD_CMD="curl"
elif command -v wget &>/dev/null; then
    DOWNLOAD_CMD="wget"
else
    log_error "Neither curl nor wget found. Please install one of them."
    exit 1
fi
SHA256_CMD=""
if command -v sha256sum &>/dev/null; then
    SHA256_CMD="sha256sum"
elif command -v shasum &>/dev/null; then
    SHA256_CMD="shasum -a 256"
else
    if [[ "$SKIP_VERIFY" -eq 0 ]]; then
        log_warn "Neither sha256sum nor shasum found. Checksum verification will be skipped."
        SKIP_VERIFY=1
    fi
fi
# ─── Locate parts file ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$PARTS_FILE" ]]; then
    PARTS_FILE="${SCRIPT_DIR}/105k_screen_measurements_urls.txt"
fi
if [[ ! -f "$PARTS_FILE" ]]; then
    log_error "Parts file not found: $PARTS_FILE"
    log_error "It should contain one .zip URL per line, e.g.:"
    log_error "  https://105kscreendata.blob.core.windows.net/105k-library-storage/2340001__2023-11-09T21_45_13-Measurement_1.zip"
    exit 1
fi
mapfile -t ALL_PARTS < <(grep -v '^\s*#' "$PARTS_FILE" | grep -v '^\s*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
TOTAL_PARTS=${#ALL_PARTS[@]}
if [[ "$TOTAL_PARTS" -eq 0 ]]; then
    log_error "Parts file is empty: $PARTS_FILE"
    exit 1
fi
log_info "Found ${TOTAL_PARTS} parts in ${PARTS_FILE}"
# ─── Apply range filter ──────────────────────────────────────────────────────
if [[ -n "$RANGE_START" && -n "$RANGE_END" ]]; then
    if [[ "$RANGE_START" -lt 1 || "$RANGE_END" -gt "$TOTAL_PARTS" || "$RANGE_START" -gt "$RANGE_END" ]]; then
        log_error "Invalid range: ${RANGE_START},${RANGE_END} (valid: 1,${TOTAL_PARTS})"
        exit 1
    fi
    PARTS=("${ALL_PARTS[@]:$((RANGE_START-1)):$((RANGE_END-RANGE_START+1))}")
    log_info "Selected range: parts ${RANGE_START} to ${RANGE_END} (${#PARTS[@]} parts)"
else
    PARTS=("${ALL_PARTS[@]}")
fi
NUM_PARTS=${#PARTS[@]}
# ─── Create output directory ─────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
# ─── Download a single file with retries ─────────────────────────────────────
download_file() {
    local url="$1"
    local dest="$2"
    if [[ -f "$dest" ]]; then
        return 0
    fi
    local attempt=0
    local tmp_dest="${dest}.tmp"
    while [[ $attempt -lt $RETRY_COUNT ]]; do
        attempt=$((attempt + 1))
        if [[ "$DOWNLOAD_CMD" == "curl" ]]; then
            if curl -fSL -o "$tmp_dest" "$url"; then
                mv "$tmp_dest" "$dest"
                return 0
            fi
        else
            if wget -q -O "$tmp_dest" "$url"; then
                mv "$tmp_dest" "$dest"
                return 0
            fi
        fi
        if [[ $attempt -lt $RETRY_COUNT ]]; then
            log_warn "  Attempt ${attempt}/${RETRY_COUNT} failed for $(basename "$url"), retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
    done
    rm -f "$tmp_dest"
    return 1
}
# ─── Verify checksum ─────────────────────────────────────────────────────────
verify_checksum() {
    local zip_file="$1"
    local sha256_file="$2"
    if [[ ! -f "$sha256_file" ]]; then
        log_warn "Checksum file missing: $(basename "$sha256_file")"
        return 1
    fi
    local expected_hash
    expected_hash=$(awk '{print $1}' "$sha256_file" | head -1)
    if [[ -z "$expected_hash" ]]; then
        log_warn "Checksum file is empty: $(basename "$sha256_file")"
        return 1
    fi
    log_info "  Verifying checksum (this may take a while for large files)..."
    local actual_hash
    actual_hash=$($SHA256_CMD "$zip_file" | awk '{print $1}')
    if [[ "$expected_hash" == "$actual_hash" ]]; then
        return 0
    else
        log_error "  Checksum mismatch for $(basename "$zip_file")"
        log_error "    Expected: ${expected_hash}"
        log_error "    Got:      ${actual_hash}"
        return 1
    fi
}
# ─── Download one part (zip + filelist + sha256) ─────────────────────────────
download_part() {
    local zip_url="$1"
    local index="$2"
    local total="$3"
    local filename
    filename="$(basename "$zip_url")"
    local stem="${filename%.zip}"
    local zip_dest="${OUTPUT_DIR}/${filename}"
    local filelist_dest="${OUTPUT_DIR}/${filename}.filelist"
    local sha256_dest="${OUTPUT_DIR}/${filename}.sha256"
    local status_file="${OUTPUT_DIR}/.verified_${stem}"
    if [[ -f "$status_file" ]]; then
        log_ok "[${index}/${total}] Already verified: ${stem}"
        return 0
    fi
    log_info "[${index}/${total}] Downloading: ${stem}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  GET ${zip_url}"
        echo "  GET ${zip_url}.filelist"
        echo "  GET ${zip_url}.sha256"
        return 0
    fi
    if ! download_file "${zip_url}.sha256" "$sha256_dest"; then
        log_error "[${index}/${total}] Failed to download checksum: ${stem}"
        return 1
    fi
    download_file "${zip_url}.filelist" "$filelist_dest" || \
        log_warn "[${index}/${total}] Filelist unavailable (non-fatal): ${stem}"
    if ! download_file "$zip_url" "$zip_dest"; then
        log_error "[${index}/${total}] Failed to download data: ${stem}"
        return 1
    fi
    if [[ "$SKIP_VERIFY" -eq 0 ]]; then
        if verify_checksum "$zip_dest" "$sha256_dest"; then
            log_ok "[${index}/${total}] Verified: ${stem}"
            touch "$status_file"
        else
            log_error "[${index}/${total}] Verification FAILED: ${stem}"
            log_error "  Removing corrupt file. Re-run the script to retry."
            rm -f "$zip_dest"
            return 1
        fi
    else
        log_ok "[${index}/${total}] Downloaded (verification skipped): ${stem}"
        touch "$status_file"
    fi
    return 0
}
# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== 105k Library Screen Dataset Downloader ==="
echo ""
echo "  Output directory : ${OUTPUT_DIR}"
echo "  Parts to download: ${NUM_PARTS} / ${TOTAL_PARTS}"
echo "  Parallel jobs    : ${PARALLEL_JOBS}"
echo "  Verify checksums : $(if [[ $SKIP_VERIFY -eq 0 ]]; then echo yes; else echo: no; fi)"
echo "  Dry run          : $(if [[ $DRY_RUN -eq 1 ]]; then echo yes; else echo no; fi)"
echo ""
if [[ "$DRY_RUN" -eq 0 ]]; then
    log_info "Starting download. Re-run this script at any time to resume."
    echo ""
fi
# ─── Main loop ────────────────────────────────────────────────────────────────
FAIL_COUNT=0
if [[ "$PARALLEL_JOBS" -gt 1 ]] && command -v parallel &>/dev/null; then
    HELPER=$(mktemp "${TMPDIR:-/tmp}/download_helper_XXXXXX.sh")
    ARGFILE=$(mktemp "${TMPDIR:-/tmp}/download_args_XXXXXX.txt")
    trap 'rm -f "$HELPER" "$ARGFILE"' EXIT
    cat > "$HELPER" <<HELPEREOF
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_DIR=$(printf '%q' "$OUTPUT_DIR")
DOWNLOAD_CMD="$DOWNLOAD_CMD"
SHA256_CMD="$SHA256_CMD"
SKIP_VERIFY=$SKIP_VERIFY
DRY_RUN=$DRY_RUN
RETRY_COUNT=$RETRY_COUNT
RETRY_DELAY=$RETRY_DELAY
$(declare -f log_info)
$(declare -f log_ok)
$(declare -f log_warn)
$(declare -f log_error)
$(declare -f download_file)
$(declare -f verify_checksum)
$(declare -f download_part)
download_part "\$1" "\$2" "\$3"
HELPEREOF
    chmod +x "$HELPER"
    for i in "${!PARTS[@]}"; do
        printf '%s %s %s\n' "${PARTS[$i]}" "$((i + 1))" "$NUM_PARTS" >> "$ARGFILE"
    done
    if ! parallel --colsep ' ' -j "$PARALLEL_JOBS" "$HELPER" {1} {2} {3} :::: "$ARGFILE"; then
        log_warn "Some downloads failed. Re-run the script to retry."
        FAIL_COUNT=1
    fi
    rm -f "$ARGFILE" "$HELPER"
    trap - EXIT
else
    if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
        log_warn "GNU parallel not found. Falling back to sequential downloads."
        log_warn "Install GNU parallel for multi-stream downloads: https://www.gnu.org/software/parallel/"
    fi
    for i in "${!PARTS[@]}"; do
        if ! download_part "${PARTS[$i]}" "$((i + 1))" "$NUM_PARTS"; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done
fi
# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "Dry run complete. No files were downloaded."
elif [[ "$FAIL_COUNT" -eq 0 ]]; then
    log_ok "All ${NUM_PARTS} parts downloaded and verified."
    log_info "Data is in: ${OUTPUT_DIR}"
else
    log_warn "${FAIL_COUNT} part(s) failed. Re-run this script to retry failed parts."
    exit 1
fi