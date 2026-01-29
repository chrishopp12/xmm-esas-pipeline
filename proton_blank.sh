#!/usr/bin/env bash
####################################################################################################
# Script Name : proton_blank.sh
# Description : Applies flare rate cuts to background files for m1.
#
# Usage:
#   ./proton_blank.sh [--rate <float>]
#
# Arguments:
#   --obs-id      <id>        Observation ID (e.g., 0881900301) [required]
#   --base-dir    <path>      Base dir with /scripts and /observation_data
#   --det         <detector>  Detector to process (e.g., m1)
#   --rate        <float>     Flare threshold rate (cts/s)
#   --verbose                  Verbosity: none|errors|all|0|1|2|yes|no            [default: errors]
#   -v | --verbose             Enable verbose SAS output
#   -h | --help                Show help
####################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"


# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_proton_blank='[proton_blank]'
push_tag "$TAG_proton_blank"
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
RATE_CLI=""



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
  --det             <detector>  Detector to process (e.g., m1)
  --rate            <float>     Flare threshold rate (cts/s)
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


while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --det)                DET="$2";                              shift 2;;
    --rate)               RATE_CLI="$2";                         shift 2;;
    --verbose)            if [[ -n "${2-}" && $2 != -* ]]; then
                          verbose_level "$2";                    shift 2; else
                          verbose_level all;                     shift  ; fi ;;
    -v)                   verbose_level all;                     shift ;;
    -h|--help)            usage;                                 exit 0;;
    *)                    echo "Unknown arg: $1"; usage;    exit 1;;
  esac
done



  # Sanity checks
  [[ -n "$OBS_ID" ]] || { log "No OBS_ID specified"; usage; exit 1; }
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
  m1) REGION=$M1_REG; FOLDER="${M1_DIR:-.}"; EXP="#XMMEA_EM && (PI>10000)"; EXP2="#XMMEA_EM"; RATE_DEFAULT=0.2; RATE_ID="MOS1_RATE";;
  m2) REGION=$M2_REG; FOLDER="${M2_DIR:-.}"; EXP="#XMMEA_EM && (PI>10000)"; EXP2="#XMMEA_EM"; RATE_DEFAULT=0.2; RATE_ID="MOS2_RATE";;
  pn) REGION=$PN_REG; FOLDER="${PN_DIR:-.}"; EXP="#XMMEA_EP && (PI>10000&&PI<12000)"; EXP2="#XMMEA_EP"; RATE_DEFAULT=0.3; RATE_ID="PN_RATE";;
  *)  die "Invalid --det: $DET (use m1|m2|pn)";;
esac

# ------------------------------------------------------------------------
# Run SAS tasks
# ------------------------------------------------------------------------
require evselect
require tabgtigen

# Get rate
RATE=$(get_rate "$RATE_CLI" "$RATE_ID" "$RATES_ENV_FILE" "$RATE_DEFAULT")

# Get blank sky
ensure_blank_for_evt ${DET}


log "Using background threshold: $RATE"


run_verbose "evselect table='${FOLDER}/${DET}_blank.fits' withrateset=Y rateset='${FOLDER}/rate${DET}bkg.fits' maketimecolumn=Y timebinsize=100 makeratecolumn=Y expression='${EXP} && (PATTERN==0)'"

run_verbose "tabgtigen table='${FOLDER}/rate${DET}bkg.fits' expression='RATE<=$RATE' gtiset='${FOLDER}/${DET}bkg_gti.fits'"

run_verbose "evselect table='${FOLDER}/${DET}_blank.fits' withfilteredset=Y filteredset='${FOLDER}/${DET}bkg_clean.fits' destruct=Y keepfilteroutput=T imagebinning=binSize imageset='${FOLDER}/${DET}bkg_image.fits' withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression='${EXP2}&& gti(${FOLDER}/${DET}bkg_gti.fits,TIME) && (PI>150)'"

pop_tag "$TAG_proton_blank"