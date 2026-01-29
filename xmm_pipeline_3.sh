#!/usr/bin/env bash
###############################################################################
# Script Name : xmm_pipeline_3.sh
# Description : Stage 3 of the XMM ESAS pipeline.
#               - Creates DET regions from WCS regions
#               - Driver for run_all.sh doing spectral processing on all detectors
#               - Runs double subtraction (subtraction2.sh)
#
# Usage examples:
#   ./xmm_pipeline_3.sh --obs-id 0881900301
#   ./xmm_pipeline_3.sh --obs-id 0881900301 --vig-mode both --detectors m1,m2
#
# Assumptions:
#   - Files have been processed for flaring (Stage 1 done)
#   - Cheese masks have been created (Stage 2 done)
#   - WCS regions created and stored as analysis/reg/src/wcs.reg and analysis/reg/bkg/wcs.reg
#
# Arguments:
#   --obs-id        <id>            Observation ID [required]
#   --base-dir      <path>          Base dir with /scripts and /observation_data         
#   --run-all       <yes|no>        Run all stages                                  [default: no]
#   --subtraction2  <yes|no>        Run subtraction2                                [default: yes]
#   --build-regions <yes|no|auto>   Rebuild config/regions.env from WCS regions     [default: auto]
#   --vig-mode      <mode>          both|blank|obs|none                             [default: both]
#   --detectors     <list>          Comma-separated detectors to run                [default: m1,m2,pn]
#   --m1-rate       <float>         MOS1 flare threshold override (cts/s)
#   --m2-rate       <float>         MOS2 flare threshold override (cts/s)
#   --pn-rate       <float>         PN flare threshold override (cts/s)
#   --m1-ccds      "<mask>"         CCDs to exclude e.g., "3,6" or "" for none
#   --m2-ccds      "<mask>"
#   --pn-ccds      "<mask>"
#   --group-min     <int>           XSPEC grouping for subtraction2                 [default: 20]
#   --verbose                  Verbosity: none|errors|all|0|1|2|yes|no             [default: errors]
#   -v | --verbose             Enable verbose SAS output
#   -h | --help                Show help
#
# Notes:
#   - If ../config/rates.env exists (from Stage 1), its values seed defaults.
#   - If ../config/regions.env (previous Stage 3 run) exists, it is sourced to set region variables.
###############################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

LOG_TAG='[STAGE 3]'
export LOG_TAG
VERBOSITY_DEFAULT=errors
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


RUN_ALL_DEFAULT="no"
RUN_SUBTRACTION2_DEFAULT="yes"
BUILD_REGIONS_DEFAULT="no"  
VIG_MODE_DEFAULT="both"
DETS_DEFAULT="m1,m2,pn"
GROUP_MIN_DEFAULT=20

# These defaults are used only after user-prompt
MOS1_RATE_DEFAULT=0.2
MOS2_RATE_DEFAULT=0.2
PN_RATE_DEFAULT=0.3





# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage(){ cat <<EOF
Usage: $(basename "$0") --obs-id <id> [options]

Options:
  --obs-id          <id>                    Observation ID (e.g., 0881900301) [required]
  --base-dir        <path>                  Base dir with /scripts and /observation_data
  --run-all         <yes|no>                Run all stages                                [default: ${RUN_ALL_DEFAULT}]
  --subtraction2    <yes|no>                Run subtraction2                              [default: ${RUN_SUBTRACTION2_DEFAULT}]
  --build-regions   <yes|no>                (Re)build regions                             [default: ${BUILD_REGIONS_DEFAULT}]
  --vig-mode        <both|blank|obs|none>   Vignetting correction                         [default: ${VIG_MODE_DEFAULT}]
  --detectors       <list>                  Detectors to process (m1,m2,pn)               [default: ${DETS_DEFAULT}]
  --m1-rate         <float>                 MOS1 flare threshold override (cts/s)
  --m2-rate         <float>                 MOS2 flare threshold override (cts/s)
  --pn-rate         <float>                 PN  flare threshold override (cts/s)
  --m1-ccds        "<mask>"                 MOS1 CCD exclusion mask (e.g., "3,6" or "" for none)
  --m2-ccds        "<mask>"                 MOS2 CCD exclusion mask
  --pn-ccds        "<mask>"                 PN CCD exclusion mask
  --group-min       <int>                   Grouping for subtraction2                     [default: ${GROUP_MIN_DEFAULT}]
  --verbose         <level>                 Verbosity: none|errors|all|0|1|2|yes|no     [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose                            Enable verbose SAS output
  -h, --help                                Show help
EOF
}




# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"
RUN_ALL="${RUN_ALL:-$RUN_ALL_DEFAULT}"
RUN_SUBTRACTION2="${RUN_SUBTRACTION2:-$RUN_SUBTRACTION2_DEFAULT}"
BUILD_REGIONS="${BUILD_REGIONS:-$BUILD_REGIONS_DEFAULT}"
VIG_MODE="${VIG_MODE:-$VIG_MODE_DEFAULT}"
DETS="${DETS:-$DETS_DEFAULT}"
GROUP_MIN="${GROUP_MIN:-$GROUP_MIN_DEFAULT}"



while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)        OBS_ID="$2"; shift 2;;
    --base-dir)      BASE_DIR="$2"; shift 2;;
    --run-all)       RUN_ALL="$(norm_flag "$2")";             shift 2;;
    --subtraction2)  RUN_SUBTRACTION2="$(norm_flag "$2")";    shift 2;;
    --build-regions) BUILD_REGIONS="$(norm_flag "$2")";       shift 2;;
    --vig-mode)      VIG_MODE="$2";                           shift 2;;
    --detectors)     DETS="$2";                               shift 2;;
    --m1-rate)       MOS1_RATE_CLI="$2";                      shift 2;;
    --m2-rate)       MOS2_RATE_CLI="$2";                      shift 2;;
    --pn-rate)       PN_RATE_CLI="$2";                        shift 2;;
    --m1-ccds)       MOS1_CCDS_CLI="$2";                      shift 2;;
    --m2-ccds)       MOS2_CCDS_CLI="$2";                      shift 2;;
    --pn-ccds)       PN_CCDS_CLI="$2";                        shift 2;;
    --group-min)     GROUP_MIN="$2";                          shift 2;;
    --verbose)       if [[ -n "${2-}" && $2 != -* ]]; then
                     verbose_level "$2";                      shift 2; else
                     verbose_level all;                       shift  ; fi ;;
    -v)              verbose_level all;                       shift ;;
    -h|--help)       usage; exit 0;;
    *)               log "Unknown arg: $1"; usage; exit 1;;
  esac
done




# Sanity checks
[[ -n "$OBS_ID" ]] || { usage; exit 1; }
[[ -d "$BASE_DIR" ]] || die "Base dir not found: $BASE_DIR"




# ------------------------------------------------------------------------
# Start Logging
# ------------------------------------------------------------------------
LOG_DIR="${BASE_DIR}/observation_data/${OBS_ID}/analysis/QA/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/xmm_pipeline_3_${OBS_ID}_$(date +%Y%m%d_%H%M%S).log"
export LOG_FILE

log "*************************************************"
log "Logging to: ${LOG_FILE#$BASE_DIR/}"
log "*************************************************"
log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  OBS_ID           = ${OBS_ID}"
log "  BASE_DIR         = ${BASE_DIR}"
log "  RUN_ALL          = ${RUN_ALL}"
log "  RUN_SUBTRACTION2 = ${RUN_SUBTRACTION2}"
log "  BUILD_REGIONS    = ${BUILD_REGIONS}"
log "  VIG_MODE         = ${VIG_MODE}"
log "  DETS             = ${DETS}"
log "  MOS1_RATE        = ${MOS1_RATE_CLI:-}"
log "  MOS2_RATE        = ${MOS2_RATE_CLI:-}"
log "  PN_RATE          = ${PN_RATE_CLI:-}"
log "  MOS1_CCDS        = '${MOS1_CCDS_CLI:-}'"
log "  MOS2_CCDS        = '${MOS2_CCDS_CLI:-}'"
log "  PN_CCDS          = '${PN_CCDS_CLI:-}'"
log "  GROUP_MIN        = ${GROUP_MIN}"
log ""






# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"


# Sanity check required files and scripts
[[ -d "$SCRIPTS_DIR" ]]      || die "Scripts directory not found: $SCRIPTS_DIR"
[[ -d "$ANALYSIS_DIR" ]]     || die "Analysis dir not found: $ANALYSIS_DIR"
[[ -d "$OBS_DIR" ]]          || die "Observation dir not found: $OBS_DIR"
[[ -f "$DOUBLE_SUBTRACTION_SH" ]]  || die "double_subtraction.sh not found: $DOUBLE_SUBTRACTION_SH"
[[ -f "$SET_SAS_VARIABLES_SH" ]]  || die "SAS init script not found: $SET_SAS_VARIABLES_SH"
[[ -d "$BLANK_SKY_DIR" ]] || die "Blank-sky directory not found: $BLANK_SKY_DIR"




# ------------------------------------------------------------------------
# Load config/env variables
# ------------------------------------------------------------------------

# -- Rates --
M1_RATE=$(get_rate "${MOS1_RATE_CLI:-}" MOS1_RATE "$RATES_ENV_FILE" "$MOS1_RATE_DEFAULT")
M2_RATE=$(get_rate "${MOS2_RATE_CLI:-}" MOS2_RATE "$RATES_ENV_FILE" "$MOS2_RATE_DEFAULT")
PN_RATE=$(get_rate "${PN_RATE_CLI:-}" PN_RATE "$RATES_ENV_FILE" "$PN_RATE_DEFAULT")


# -- CCDs --
M1_CCDS=$(get_ccds "${EXCLUDE_CCDS_M1_CLI:-}" EXCLUDE_CCDS_M1 "$CCDS_ENV_FILE" m1)
M2_CCDS=$(get_ccds "${EXCLUDE_CCDS_M2_CLI:-}" EXCLUDE_CCDS_M2 "$CCDS_ENV_FILE" m2)
PN_CCDS=$(get_ccds "${EXCLUDE_CCDS_PN_CLI:-}" EXCLUDE_CCDS_PN "$CCDS_ENV_FILE" pn)





# ------------------------------------------------------------------------
# Stage 3.0: Initialize SAS and HEASoft
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 3.0: Initialize SAS and HEASoft"
log "-------------------------------------------------"


log "Sourcing SAS variables (build=false) from: $SET_SAS_VARIABLES_SH"

source "$SET_SAS_VARIABLES_SH" --obs-id "$OBS_ID" --build-ccf false --run-sasversion false --verbose "$SAS_VERBOSE_LEVEL"


# Check SAS loaded properly
if ! command -v sasversion >/dev/null 2>&1; then
  die "sasversion not in PATH after sourcing. Check $SET_SAS_VARIABLES_SH"
fi



# ------------------------------------------------------------------------
# Stage 3.1: (Re)build regions
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 3.1: (Re)build regions"
log "-------------------------------------------------"


if [[ "$BUILD_REGIONS" == "yes" ]]; then
    log "(Re)building config/regions.env from WCS DS9 regions…"
    [[ -s "${ANALYSIS_DIR}/reg/src/wcs.reg" ]] || die "Missing ${ANALYSIS_DIR}/reg/src/wcs.reg"
    [[ -s "${ANALYSIS_DIR}/reg/bkg/wcs.reg" ]] || die "Missing ${ANALYSIS_DIR}/reg/bkg/wcs.reg"

    # helper converts WCS to DET and writes config/regions.env
    source "${MAKE_REGIONS_SH}" --obs-id "$OBS_ID" --base-dir "$BASE_DIR" --verbose "$SAS_VERBOSE_LEVEL"
fi

load_regions 




# ------------------------------------------------------------------------
# Stage 3.2: Run all detectors
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 3.2: Run all detectors"
log "-------------------------------------------------"


if [[ "$RUN_ALL" == "yes" ]]; then
    log "Running run_det.sh for detectors: $DETS (vig=$VIG_MODE)…"
    cd "$ANALYSIS_DIR"

    for DET in ${DETS//,/ }; do
        log "---- Running run_det.sh for $DET ----"

        DET_UPPER="$(echo "$DET" | tr '[:lower:]' '[:upper:]')"   
        DET_RATE_VAR="${DET_UPPER}_RATE"
        DET_CCDS_VAR="${DET_UPPER}_CCDS"
        DET_RATE="${!DET_RATE_VAR-}"      
        DET_CCDS="${!DET_CCDS_VAR-}"

        bash ${SCRIPTS_DIR}/run_det.sh \
            --obs-id "$OBS_ID" \
            --base-dir "$BASE_DIR" \
            --det "$DET" \
            --vig-mode "$VIG_MODE" \
            ${DET_RATE:+--bkg-rate "$DET_RATE"} \
            ${DET_CCDS:+--exclude-ccds "$DET_CCDS"} \
            --verbose "$SAS_VERBOSE_LEVEL"
    done

    log "run_det.sh complete for all detectors."
fi



# ------------------------------------------------------------------------
# Stage 3.3: Run double subtraction
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 3.3: Run double subtraction"
log "-------------------------------------------------"

if [[ "$RUN_SUBTRACTION2" == "yes" ]]; then
  (
    cd "$ANALYSIS_DIR"
    bash "$DOUBLE_SUBTRACTION_SH" --detectors "$DETS" --group-min "$GROUP_MIN" --verbose "$SAS_VERBOSE_LEVEL"
  )
fi

log "Stage 3 complete. Next: images (make_images.sh) or spectra (run_xspec.sh)."