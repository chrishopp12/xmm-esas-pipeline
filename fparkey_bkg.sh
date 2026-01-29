#!/usr/bin/env bash
####################################################################################################
# Script Name : fparkey_bkg_m1.sh
# Description : Updates DATE-OBS and DATE-END in background files for m1.
#
# Usage:
#   ./fparkey_bkg_m1.sh --obs-id <id> --base-dir <path> --det <detector> [options]
#
# Arguments:
#   --obs-id          <id>          Observation ID (e.g., 0881900301) [required]
#   --base-dir        <path>        Base dir with /scripts and /observation_data
#   --det            <detector>     Detector to process (e.g., m1)
#   --date-obs       "<string>"     Start date/time in ISO format
#   --date-end       "<string>"     End date/time in ISO format
#   --verbose                       Verbosity: none|errors|all|0|1|2|yes|no        [default: errors]
#   -v | --verbose                  Enable verbose SAS output
#   -h | --help                     Show help
####################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"


# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_fparkey='[fparkey_bkg]'
push_tag "$TAG_fparkey"
VERBOSITY_DEFAULT="${SAS_VERBOSE_LEVEL:-errors}"
verbose_level "$VERBOSITY_DEFAULT"


# ------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------
OBS_ID_DEFAULT=""

# BASE_DIR_DEFAULT Priority: env XMM_BASE_DIR > env XMM_BASE_DIR > derived from script location > pwd
if [[ -n "${XMM_BASE_DIR:-}" ]]; then
  BASE_DIR_DEFAULT="${XMM_BASE_DIR}"
else
  BASE_DIR_DEFAULT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P 2>/dev/null || pwd -P)"
fi

BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"
DET_DEFAULT=""
DATE_OBS_DEFAULT=""
DATE_END_DEFAULT=""
# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") --obs-id <id> [options]

Options:
  --obs-id          <id>        Observation ID (e.g., 0881900301) [required]
  --base-dir        <path>      Base dir with /scripts and /observation_data
  --det            <detector>   Detector to process (e.g., m1)
  --date-obs       "<string>"   Start date/time in ISO format
  --date-end       "<string>"   End date/time in ISO format
  --verbose         <level>     Verbosity: none|errors|all|0|1|2|yes|no     [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose                Enable verbose SAS output
  -h, --help                    Show help
EOF
}



# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# Use defaults if not provided
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"
DET="${DET:-$DET_DEFAULT}"
DATE_OBS="${DATE_OBS:-$DATE_OBS_DEFAULT}"
DATE_END="${DATE_END:-$DATE_END_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --det)                DET="$2";                              shift 2;;
    --date-obs)           DATE_OBS="$2";                         shift 2;;
    --date-end)           DATE_END="$2";                         shift 2;;
    --verbose)            if [[ -n "${2-}" && $2 != -* ]]; then
                          verbose_level "$2";                    shift 2; else
                          verbose_level all;                     shift  ; fi ;;
    -v)                   verbose_level all;                     shift ;;
    -h|--help)            usage;                                 exit 0;;
    *)                    echo "Unknown arg: $1"; usage;    exit 1;;
  esac
done



# Sanity checks
[[ -n "$OBS_ID" ]] || { usage; exit 1; }
[[ -d "$BASE_DIR" ]] || die "Base dir not found: $BASE_DIR"




# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"



# -- Detector file identifiers --

# Try to infer detector if not specified
if [[ -z "$DET" ]]; then
  case "$(basename "$PWD")" in
    m1|m2|pn) DET="$(basename "$PWD")";;
    *)        die "Must specify --det (m1, m2, or pn)";;
  esac
fi

case "$DET" in
  m1|m2|pn) ;;
  *)        die "Invalid detector specified: $DET (must be m1, m2, or pn)";;
esac

FOLDER="$(dir_of "$DET")"
EVENT_FILE="$(evt_of "$DET")"
BLANK_FILE="$(blank_of "$DET")"
SHORT_BLANK="${BLANK_FILE#$OBS_DIR/}"
SHORT_EVENT="${EVENT_FILE#$OBS_DIR/}"

[[ -d "$FOLDER" ]] || die "Detector folder not found: $FOLDER"
[[ -f "$EVENT_FILE" ]] || die "Event file not found: $EVENT_FILE"
[[ -f "$BLANK_FILE" ]] || die "Blank sky file not found: $BLANK_FILE"


# ------------------------------------------------------------------------
# Run fparkey
# ------------------------------------------------------------------------
require fparkey

# --- Get dates ---
log "Determining DATE-OBS and DATE-END from $SHORT_EVENT..."
if [[ -z "$DATE_OBS" || -z "$DATE_END" ]]; then
   [[ -f "$EVENT_FILE" ]] || die "Event file not found: $EVENT_FILE"
   [[ -z "$DATE_OBS" ]] && DATE_OBS="$(header_val "$EVENT_FILE" DATE-OBS)"
   [[ -z "$DATE_END" ]] && DATE_END="$(header_val "$EVENT_FILE" DATE-END)"
fi

[[ -n "$DATE_OBS" ]] || die "Could not determine DATE-OBS from $EVENT_FILE"
[[ -n "$DATE_END" ]] || die "Could not determine DATE-END from $EVENT_FILE"


# --- Actually write dates to all HDUs ---
log "Writing DATE-OBS=$DATE_OBS DATE-END=$DATE_END to $SHORT_BLANK [0..13]..."
for num in {0..13}; do
  log "  Writing to HDU ${num}…"
  fparkey "$DATE_OBS" "$BLANK_FILE"+${num} DATE-OBS add=yes
  fparkey "$DATE_END" "$BLANK_FILE"+${num} DATE-END add=yes
done

log "Finished writing dates to $SHORT_BLANK"

pop_tag "$TAG_fparkey"