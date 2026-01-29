#!/usr/bin/env bash
#######################################################################################################
# Script Name : light_curves.sh
# Description : Generates light curves for flare filtering.
#
# Usage:
#   ./light_curves.sh [options]
#
# Options:
#   --obs-id       <id>            Observation ID [required]
#   --base-dir     <path>          Base dir with /scripts and /observation_data
#   --timebin      <int>           Time bin size for light curves              [default: 100]
#   --mos-elow     <float>         Min energy (eV) for MOS detectors           [default: 10000]
#   --pn-elow      <float>         Min energy (eV) for PN detector             [default: 10000]
#   --pn-ehigh     <float>         Max energy (eV) for PN detector             [default: 12000]
#   --verbose                      Verbosity: none|errors|all|0|1|2|yes|no     [default: errors]
#   -v | --verbose                 Enable verbose SAS output
#   -h | --help                    Show help
#######################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_light_curves='[light_curves]'
push_tag "$TAG_light_curves"
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
TIMEBIN_DEFAULT=100
MOS_ELOW_DEFAULT=10000
PN_ELOW_DEFAULT=10000
PN_EHIGH_DEFAULT=12000


# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --obs-id       <id>     Observation ID (e.g., 0881900301) [required]
  --base-dir     <path>   Base dir with /scripts and /blank_all
  --timebin      <int>    Time bin size for light curves              [default: "$TIMEBIN_DEFAULT"]
  --mos-elow     <float>  Min energy (eV) for MOS detectors           [default: "$MOS_ELOW_DEFAULT"]
  --pn-elow      <float>  Min energy (eV) for PN detector             [default: "$PN_ELOW_DEFAULT"]
  --pn-ehigh     <float>  Max energy (eV) for PN detector             [default: "$PN_EHIGH_DEFAULT"]
  --verbose               Verbosity: none|errors|all|0|1|2|yes|no     [default: "$VERBOSITY_DEFAULT"]
  -v | --verbose          Enable verbose SAS output
  -h | --help             Show help
EOF
}


# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

# -- Reset others to defaults --
TIMEBIN="${TIMEBIN_DEFAULT}"
MOS_ELOW="${MOS_ELOW_DEFAULT}"
PN_ELOW="${PN_ELOW_DEFAULT}"
PN_EHIGH="${PN_EHIGH_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --timebin)            TIMEBIN="$2";                          shift 2;;
    --mos-elow)           MOS_ELOW="$2";                         shift 2;;
    --pn-elow)            PN_ELOW="$2";                          shift 2;;
    --pn-ehigh)           PN_EHIGH="$2";                         shift 2;;
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
# Start Logging
# ------------------------------------------------------------------------
log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  TIMEBIN       = ${TIMEBIN}"
log "  MOS_ELOW      = ${MOS_ELOW}"
log "  PN_ELOW       = ${PN_ELOW}"
log "  PN_EHIGH      = ${PN_EHIGH}"
log ""


# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"

# Sanity check required files and scripts
[[ -d "$SCRIPTS_DIR" ]] || die "Scripts directory not found: $SCRIPTS_DIR"
[[ -f "$MOS1_S001_FITS" ]] || die "MOS1 event file not found: $MOS1_S001_FITS"
[[ -f "$MOS2_S002_FITS" ]] || die "MOS2 event file not found: $MOS2_S002_FITS"
[[ -f "$PN_S003_FITS"   ]] || die "PN event file not found: $PN_S003_FITS"


# ------------------------------------------------------------------------
# Generate light curves
# ------------------------------------------------------------------------
require evselect

log "Generating MOS1 light curve: PI > ${MOS_ELOW}, bin=${TIMEBIN}..."
run_verbose "evselect table=${MOS1_S001_FITS} withrateset=Y rateset=ratem1.fits maketimecolumn=Y timebinsize=$TIMEBIN makeratecolumn=Y expression=\"#XMMEA_EM && (PI>$MOS_ELOW) && (PATTERN==0)\""

log "Generating MOS2 light curve: PI > ${MOS_ELOW}, bin=${TIMEBIN}..."
run_verbose "evselect table=${MOS2_S002_FITS} withrateset=Y rateset=ratem2.fits maketimecolumn=Y timebinsize=$TIMEBIN makeratecolumn=Y expression=\"#XMMEA_EM && (PI>$MOS_ELOW) && (PATTERN==0)\""

log "Generating PN light curve: ${PN_ELOW} < PI < ${PN_EHIGH}, bin=${TIMEBIN}..."
run_verbose "evselect table=${PN_S003_FITS} withrateset=Y rateset=ratepn.fits maketimecolumn=Y timebinsize=$TIMEBIN makeratecolumn=Y expression=\"#XMMEA_EP && (PI>$PN_ELOW && PI<$PN_EHIGH) && (PATTERN==0)\""

log "Light curve generation complete."

pop_tag "$TAG_light_curves"