#!/usr/bin/env bash
######################################################################################
# Script Name : create_events.sh
# Description : Used in Stage 2 (mask prep) — runs chains and
#               applies ESAS flare filtering to create cleaned event files in mask/.
#               - Runs emchain/epchain (+PN OOT)
#               - Normalizes event filenames for MOS1, MOS2, PN, PN OOT
#               - Applies espfilt (standard ESAS flare filtering) to all
#                 detectors, creating *_clean.fits for use in mask creation
#
# Usage:
#   ./create_events.sh [-v|--verbose <level>] [--filter <yes|no>] [--run-chains <yes|no>]
#
# Example:
#   ./create_events.sh --verbose 2
#
# Arguments:
#   --obs-id     <id>       Observation ID [required]
#   --base-dir   <path>     Base dir with /scripts and /observation_data
#   --directory  <path>     Directory to process
#   --run-filter <yes|no>   Apply flare filtering                 [default: no]
#   --run-chains <yes|no>   Run chains                            [default: yes]
#   --verbose    <level>    Verbosity: none|errors|all|0|1|2|yes|no [default: errors]
#   -v | --verbose Enable verbose SAS output
#   -h | --help     Show help
#
# Notes:
#   - This step is separate from Stage 1 flare filtering, which uses flat
#     rate cuts, later applied to blank sky files.
#   - This step must be run inside the mask/ directory and will overwrite
#     existing files if present.
#   - Outputs are required for subsequent cheese/mask steps (step3.sh).
####################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_create_events='[create_events]'
push_tag "$TAG_create_events"
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
DIRECTORY_DEFAULT="$(pwd)"
RUN_FILTER_DEFAULT=no
RUN_CHAINS_DEFAULT=yes


# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  ./$(basename "$0") [--verbose <level>]

Options:
  --obs-id         <id>      Observation ID (e.g., 0881900301) [required]
  --base-dir       <path>    Base dir with /scripts and /blank_all
  --directory      <path>    Directory to process.                   [default: ${DIRECTORY_DEFAULT}]
  --run-filter     <yes|no>  Apply flare filtering                   [default: ${RUN_FILTER_DEFAULT}]
  --run-chains     <yes|no>  Run chains                              [default: ${RUN_CHAINS_DEFAULT}]
  --verbose        <level>   Verbosity: none|errors|all|0|1|2|yes|no [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose             Enable verbose SAS output
  -h | --help                Show help
EOF
}


# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

# -- Reset others to defaults --
DIRECTORY="${DIRECTORY_DEFAULT}"
RUN_FILTER="${RUN_FILTER_DEFAULT}"
RUN_CHAINS="${RUN_CHAINS_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --directory)          DIRECTORY="$2";                        shift 2;;
    --run-filter)         RUN_FILTER="$(norm_flag "$2")";        shift 2;;
    --run-chains)         RUN_CHAINS="$(norm_flag "$2")";        shift 2;;
    --verbose)            if [[ -n "${2-}" && $2 != -* ]]; then
                          verbose_level "$2";                    shift 2; else
                          verbose_level all;                     shift  ; fi ;;
    -v | --print)         verbose_level all;                     shift ;;
    -h|--help)            usage;                                 exit 0;;
    *)                    echo "Unknown arg: $1"; usage;    exit 1;;
  esac
done


# Sanity checks
[[ -n "$OBS_ID" ]] || { log "No OBS_ID specified"; usage; exit 1; }
[[ -d "$BASE_DIR" ]] || die "Base dir not found: $BASE_DIR"
[[ -d "$DIRECTORY" ]] || die "Directory not found: $DIRECTORY"


# ------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------
log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  OBS_ID         = ${OBS_ID}"
log "  DIRECTORY      = ${DIRECTORY}"
log "  RUN_FILTER     = ${RUN_FILTER}"
log "  RUN_CHAINS     = ${RUN_CHAINS}"
log ""


# ------------------------------------------------------------------------
# Run SAS Tasks
# ------------------------------------------------------------------------
cd "$DIRECTORY"
if [[ "$RUN_CHAINS" == "yes" ]]; then
  require emchain
  require epchain

  # -- Run em/epchain --
  log "Running emchain..."
  run_verbose "emchain"

  log "Running epchain..."
  run_verbose "epchain"

  log "Running epchain incl. OOT..."
  run_verbose "epchain withoutoftime=true"

  # -- Copy event files --
  cp *M1S001*EVL* mos1S001.fits
  cp *M2S002*EVL* mos2S002.fits
  cp *PN*IEVL* pnS003.fits
  cp *PN*OEVL* pnS003-oot.fits

  # cp *M1U002*EVL* mos1S001.fits
  # cp *M2U002*EVL* mos2S002.fits
  # cp *PN*IEVL* pnS003.fits
  # cp *PN*OEVL* pnS003-oot.fits


  # cp *M1S001*EVL* mos1S001a.fits
  # cp *M1U003*EVL* mos1U003.fits
  # cp *M2S002*EVL* mos2S002a.fits
  # cp *M2U003*EVL* mos2U003.fits
  # cp *PN*IEVL* pnS003.fits
  # cp *PN*OEVL* pnS003-oot.fits

  # merge set1=mos1S001a.fits set2=mos1U003.fits outset=mos1S001.fits
  # merge set1=mos2S002a.fits set2=mos2U003.fits outset=mos2S002.fits
fi

if [[ "$RUN_FILTER" == "yes" ]]; then
  require espfilt

  # -- Filter event files --
  log "Filtering event files..."
  run_verbose "espfilt eventfile='mos1S001.fits' elow=2500 ehigh=8500 withsmoothing=yes smooth=51 rangescale=10.0 allowsigma=3.0 method=histogram keepinterfiles=false"
  run_verbose "espfilt eventfile='mos2S002.fits' elow=2500 ehigh=8500 withsmoothing=yes smooth=51 rangescale=10.0 allowsigma=3.0 method=histogram keepinterfiles=false"
  run_verbose "espfilt eventfile='pnS003.fits' elow=2500 ehigh=8500 withsmoothing=yes smooth=51 rangescale=25.0 allowsigma=3.0 method=histogram withoot=Y ootfile='pnS003-oot.fits' keepinterfiles=false"

log "Finished filtering event files."
fi


log "Finished creating event files."
cd "$DIRECTORY_DEFAULT"
pop_tag "$TAG_create_events"
