#!/usr/bin/env bash
###############################################################################
# Script Name : filter_flares.sh
# Description : Applies flare rate thresholds and generates filtered event files.
#
# Usage:
#   ./filter_flares.sh [options]
#
# Arguments:
#   --obs-id             <id>       Observation ID [required]
#   --base-dir           <path>     Root dir with /scripts and /observation_data
#   --mos1-rate <float>             MOS1 flare threshold (cts/s)
#   --mos2-rate <float>             MOS2 flare threshold (cts/s)
#   --pn-rate   <float>             PN flare threshold (cts/s)
#   --verbose                       Verbosity: none|errors|all|0|1|2|yes|no     [default: errors]
#   -v | --verbose                  Enable verbose SAS output
#   -h | --help                     Show help
###############################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"
TAG_filter_flares='[filter_flares]'
push_tag "$TAG_filter_flares"
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
MOS1_RATE_DEFAULT=0.2   # Defaults are only used in a fallback prompt to user
MOS2_RATE_DEFAULT=0.2
PN_RATE_DEFAULT=0.3


# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --obs-id        <id>            Observation ID (e.g., 0881900301) [required]
  --base-dir      <path>          Base dir with /scripts and /blank_all
  --mos1-rate     <float>         MOS1 flare threshold (cts/s)
  --mos2-rate     <float>         MOS2 flare threshold (cts/s)
  --pn-rate       <float>         PN flare threshold (cts/s)
  --verbose                       Verbosity: none|errors|all|0|1|2|yes|no     [default: "$VERBOSE_DEFAULT"]
  -v | --verbose                  Enable verbose SAS output
  -h | --help                     Show help
EOF
}


# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

# Do NOT set rates to defaults -> could overwrite

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --mos1-rate)          MOS1_RATE_CLI="$2";                    shift 2;;
    --mos2-rate)          MOS2_RATE_CLI="$2";                    shift 2;;
    --pn-rate)            PN_RATE_CLI="$2";                      shift 2;;
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



# ------------------------------------------------------------------------
# Set rates
# ------------------------------------------------------------------------

MOS1_RATE=$(get_rate "${MOS1_RATE_CLI:-}" "MOS1_RATE" "$RATES_ENV_FILE" "$MOS1_RATE_DEFAULT")
MOS2_RATE=$(get_rate "${MOS2_RATE_CLI:-}" "MOS2_RATE" "$RATES_ENV_FILE" "$MOS2_RATE_DEFAULT")
PN_RATE=$(get_rate "${PN_RATE_CLI:-}" "PN_RATE" "$RATES_ENV_FILE" "$PN_RATE_DEFAULT")


# ------------------------------------------------------------------------
# Validate inputs (how you get this far is a mystery)
# ------------------------------------------------------------------------
[[ -n "$MOS1_RATE" ]] || die "Missing MOS1_RATE (set via CLI, env, or config)"
[[ -n "$MOS2_RATE" ]] || die "Missing MOS2_RATE (set via CLI, env, or config)"
[[ -n "$PN_RATE"   ]] || die "Missing PN_RATE (set via CLI, env, or config)"


# ------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------

log "Called as: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  MOS1_RATE    = ${MOS1_RATE}"
log "  MOS2_RATE    = ${MOS2_RATE}"
log "  PN_RATE      = ${PN_RATE}"
log ""


log "Using thresholds: MOS1=$MOS1_RATE, MOS2=$MOS2_RATE, PN=$PN_RATE"


# ------------------------------------------------------------------------
# Run SAS tasks
# ------------------------------------------------------------------------
require tabgtigen
require evselect

log "Generating GTIs..."
run_verbose "tabgtigen table=$ANALYSIS_DIR/ratem1.fits expression=\"RATE<=$MOS1_RATE\" gtiset=$ANALYSIS_DIR/mos1S001-gti.fits"
run_verbose "tabgtigen table=$ANALYSIS_DIR/ratem2.fits expression=\"RATE<=$MOS2_RATE\" gtiset=$ANALYSIS_DIR/mos2S002-gti.fits"
run_verbose "tabgtigen table=$ANALYSIS_DIR/ratepn.fits expression=\"RATE<=$PN_RATE\" gtiset=$ANALYSIS_DIR/pnS003-gti.fits"

log "Generating filtered event sets..."
run_verbose "evselect table=$MOS1_S001_FITS withfilteredset=Y filteredset=$ANALYSIS_DIR/mos1S001-allevc.fits destruct=Y keepfilteroutput=T imageset=$ANALYSIS_DIR/mos1S001-allimc.fits withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression=\"#XMMEA_EM && gti(mos1S001-gti.fits,TIME) && (PI>150)\""
run_verbose "evselect table=$MOS2_S002_FITS withfilteredset=Y filteredset=$ANALYSIS_DIR/mos2S002-allevc.fits destruct=Y keepfilteroutput=T imageset=$ANALYSIS_DIR/mos2S002-allimc.fits withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression=\"#XMMEA_EM && gti(mos2S002-gti.fits,TIME) && (PI>150)\""
run_verbose "evselect table=$PN_S003_FITS withfilteredset=Y filteredset=$ANALYSIS_DIR/pnS003-allevc.fits destruct=Y keepfilteroutput=T imageset=$ANALYSIS_DIR/pnS003-allimc.fits withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression=\"#XMMEA_EP && gti(pnS003-gti.fits,TIME) && (PI>150)\""
run_verbose "evselect table=$PN_S003_OOT_FITS withfilteredset=Y filteredset=$ANALYSIS_DIR/pnS003-allevcoot.fits destruct=Y keepfilteroutput=T imageset=$ANALYSIS_DIR/pnS003-allimcoot.fits withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression=\"#XMMEA_EP && gti(pnS003-gti.fits,TIME) && (PI>150)\""

log "Flare filtering complete."

pop_tag "$TAG_filter_flares"
