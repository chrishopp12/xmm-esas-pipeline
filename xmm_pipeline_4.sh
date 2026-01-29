#!/usr/bin/env bash

###############################################################################
# Script Name : xmm_pipeline_4.sh
# Description : Stage 4 of the XMM ESAS pipeline.
#               Runs make_images.sh and/or run_xspec.sh with CCD and parameter
#               values automatically loaded from config.
#
# Usage Examples:
#   ./xmm_pipeline_4.sh --obs-id 0881900301 --run-images yes --run-xspec no
#
# Options:
#   --obs-id       <id>        Observation ID (required)
#   --base-dir     <path>      Base dir with /scripts and /observation_data
#   --run-images   <yes|no>    Run imaging step (default: yes)
#   --run-xspec    <yes|no>    Run XSPEC step (default: yes)
#   --m1-ccds      "<mask>"    MOS1 CCDs to exclude e.g., "3,6" or "" for none
#   --m2-ccds      "<mask>"    MOS2 CCDs to exclude 
#   --pn-ccds      "<mask>"    PN CCDs to exclude 
#   --z <float>                Cluster redshift
#   --nh <float>               Galactic hydrogen column density (1e22 cm^-2)
###############################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

LOG_TAG='[STAGE 4]'
export LOG_TAG
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

RUN_IMAGES_DEFAULT="yes"
RUN_XSPEC_DEFAULT="yes"




# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------

usage(){ cat <<EOF
Usage: $(basename "$0") [options]
  --obs-id           <id>          Observation ID (e.g., 0881900301) [required]
  --base-dir         <path>        Base dir with /scripts and /blank_all
  --run-images       <yes|no>      Run make_images.sh                            [default: $RUN_IMAGES_DEFAULT]
  --run-xspec        <yes|no>      Run run_xspec.sh                              [default: $RUN_XSPEC_DEFAULT]
  --m1-ccds         "<mask>"       MOS1 CCD exclusion mask (e.g., "3,6" or "" for none)
  --m2-ccds         "<mask>"       MOS2 CCD exclusion mask 
  --pn-ccds         "<mask>"       PN CCD exclusion mask - Currently always TTTT
  --z                <float>       Cluster redshift
  --nh               <float>       Galactic hydrogen column density (1e22 cm^-2)
  --verbose          <level>       Verbosity: none|errors|all|0|1|2|yes|no        [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose                   Enable verbose SAS output 
  -h | --help                      Show help
EOF
}



# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"
RUN_IMAGES="${RUN_IMAGES:-$RUN_IMAGES_DEFAULT}"
RUN_XSPEC="${RUN_XSPEC:-$RUN_XSPEC_DEFAULT}"


while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)         OBS_ID="$2";                           shift 2;;
    --base-dir)       BASE_DIR="$2";                         shift 2;;
    --run-images)     RUN_IMAGES="$(norm_flag "$2")";        shift 2;;
    --run-xspec)      RUN_XSPEC="$(norm_flag "$2")";         shift 2;;
    --m1-ccds)        MOS1_CCDS_CLI="$2";                    shift 2;;
    --m2-ccds)        MOS2_CCDS_CLI="$2";                    shift 2;;
    --pn-ccds)        PN_CCDS_CLI="$2";                      shift 2;;
    --z)              Z="$2";                                shift 2;;
    --nh)             NH="$2";                               shift 2;;
    --verbose)        if [[ -n "${2-}" && $2 != -* ]]; then
                      verbose_level "$2";                    shift 2; else
                      verbose_level all;                     shift  ; fi ;;
    -v)               verbose_level all;                     shift ;;
    -h|--help)        usage;                                 exit 0;;
    *)                echo "Unknown arg: $1"; usage;         exit 1;;
  esac
done



# Sanity checks
[[ -n "$OBS_ID" ]] || { log "No OBS_ID specified"; usage; exit 1; }
[[ -d "$BASE_DIR" ]] || die "Base dir not found: $BASE_DIR"




# ------------------------------------------------------------------------
# Start Logging
# ------------------------------------------------------------------------
LOG_DIR="${BASE_DIR}/observation_data/${OBS_ID}/analysis/QA/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/xmm_pipeline_4_${OBS_ID}_$(date +%Y%m%d_%H%M%S).log"
export LOG_FILE

log "*************************************************"
log "Logging to: ${LOG_FILE#$BASE_DIR/}"
log "*************************************************"
log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  RUN_IMAGES    = ${RUN_IMAGES}"
log "  RUN_XSPEC     = ${RUN_XSPEC}"
log "  MOS1_CCDS     = '${MOS1_CCDS_CLI:-}'"
log "  MOS2_CCDS     = '${MOS2_CCDS_CLI:-}'"
log "  PN_CCDS       = '${PN_CCDS_CLI:-}'"
log "  Z             = ${Z:-}"
log "  NH            = ${NH:-}"
log ""




# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"

# Sanity check required files and scripts
[[ -d "$MASK_DIR" ]] || die "Mask directory not found: $MASK_DIR"
[[ -d "$IMAGE_DIR" ]] || die "Image directory not found: $IMAGE_DIR"
[[ -d "$SUBTRACTION_DIR" ]] || die "Subtraction directory not found: $SUBTRACTION_DIR"
[[ -d "$CONFIG_DIR" ]] || die "Config directory not found: $CONFIG_DIR"
[[ -f "$MAKE_IMAGES_SH" ]] || die "make_images.sh not found: $MAKE_IMAGES_SH"
[[ -f "$RUN_XSPEC_SH" ]] || die "run_xspec.sh not found: $RUN_XSPEC_SH"
[[ -f "$SET_SAS_VARIABLES_SH" ]] || die "SAS init script not found: $SET_SAS_VARIABLES_SH"




# ------------------------------------------------------------------------
# Stage 4.0: Initialize SAS and HEASoft
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 4.0: Initialize SAS and HEASoft"
log "-------------------------------------------"
log "Sourcing SAS variables (build=false) from: ${SET_SAS_VARIABLES_SH##*/}"

# Temporarily allow undefined variables for sourcing
set +u
source "$SET_SAS_VARIABLES_SH" --obs-id "$OBS_ID" --build-ccf false --run-sasversion false --verbose "$SAS_VERBOSE_LEVEL"
set -u

# Check SAS loaded properly
if ! command -v sasversion >/dev/null 2>&1; then
  die "sasversion not in PATH after sourcing. Check $SET_SAS_VARIABLES_SH"
fi




# ------------------------------------------------------------------------
# Stage 4.1: Run make_images.sh
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 4.1: Run images script"
log "-------------------------------------------"
if [[ "$RUN_IMAGES" == "yes" ]]; then


  log "Running make_images.sh..."
  args=()
  if [[ -n "${MOS1_CCDS_CLI:-}" ]]; then
      args+=(--m1-ccds "$MOS1_CCDS_CLI")
  fi
  if [[ -n "${MOS2_CCDS_CLI:-}" ]]; then
      args+=(--m2-ccds "$MOS2_CCDS_CLI")
  fi
  if [[ -n "${PN_CCDS_CLI:-}" ]]; then
      args+=(--pn-ccds "$PN_CCDS_CLI")
  fi

  args+=(--verbose "$SAS_VERBOSE_LEVEL")

  bash "$MAKE_IMAGES_SH" "${args[@]}"
else
  log "Skipping make_images.sh"
fi




# ------------------------------------------------------------------------
# Stage 4.2: Run run_xspec.sh
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 4.2: Run XSPEC script"
log "-------------------------------------------"
if [[ "$RUN_XSPEC" == "yes" ]]; then
    log "Running run_xspec.sh..."

    bash "${RUN_XSPEC_SH}" ${Z:+--z "$Z"} ${NH:+--nh "$NH"} --verbose "$SAS_VERBOSE_LEVEL"
else
    log "Skipping run_xspec.sh"
fi

log "Stage 4 complete."
