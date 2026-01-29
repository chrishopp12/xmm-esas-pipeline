#!/usr/bin/env bash
###############################################################################
# Script Name : resolve_paths.sh
# Description : Defines all pipeline paths from BASE_DIR and OBS_ID.
#               - Accepts args: resolve_paths.sh <BASE_DIR> <OBS_ID>
#               - Or inherits from environment variables
#               - Must be sourced: source ./resolve_paths.sh
#
# Usage:
#   source resolve_paths.sh --obs-id <id> --base-dir <path> [--verbose <level>]
#
# Example:
#   source ./scripts/resolve_paths.sh --obs-id "0881900301" --base-dir "/Users/you/Desktop/XMM"
# Arguments:
#   --obs-id             <id>       Observation ID [required]
#   --base-dir           <path>     Root dir with /scripts and /observation_data
#   --verbose                       Verbosity: none|errors|all|0|1|2|yes|no     [default: errors]
#   -v | --verbose                  Enable verbose SAS output
#   -h | --help                     Show help
###############################################################################


# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"
TAG='[resolve_paths]'
push_tag "$TAG"
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




# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
usage_rp() {
  cat <<EOF
Usage:
  source $(basename "$0") --obs-id <id> --base-dir <path> [--verbose <level>]

Options:
  --obs-id <id>        Observation ID (e.g., 0881900301) [required]
  --base-dir <path>    Base directory with /scripts and /observation_data [required]
  --verbose <level>    Verbosity: none|errors|all|0|1|2|yes|no [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose       Enable verbose SAS output
  -h | --help          Show help
EOF
}

fi


# ------------------------------------------------------------------------
# Error handling
# ------------------------------------------------------------------------
# Must be sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  die "This script must be sourced: source $0 [base_dir] [obs_id]" >&2
fi






# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --verbose)            if [[ -n "${2-}" && $2 != -* ]]; then
                          verbose_level "$2";                    shift 2; else
                          verbose_level all;                     shift  ; fi ;;
    -v | --print)         verbose_level all;                     shift ;;
    -h|--help)            usage_rp;                                 exit 0;;
    *)                    echo "Unknown arg: $1"; usage;    exit 1;;
  esac
done


# Use defaults if not provided
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

# Validate required variables
if [[ -z "$OBS_ID" || -z "$BASE_DIR" ]]; then
  log_error "BASE_DIR and OBS_ID must be set through CLI or env."
  usage_rp
  return 1
fi

# # Prevent redefinition
# if [[ -n "${__RESOLVE_PATHS_LOADED:-}" ]]; then
#   pop_tag "$TAG_RP"
#   return 0
# fi
# export __RESOLVE_PATHS_LOADED=1


# ------------------------------------------------------------------------
# Export paths
# ------------------------------------------------------------------------
export BASE_DIR
export OBS_ID

# -- Core directories --
export SCRIPTS_DIR="${BASE_DIR}/scripts"
export OBS_DIR="${BASE_DIR}/observation_data/${OBS_ID}"
export ODF_DIR="${OBS_DIR}/odf"
export ANALYSIS_DIR="${OBS_DIR}/analysis"

# -- Subdirectories --
export TEMPLATE_DIR="${BASE_DIR}/blank_all"
export M1_DIR="${ANALYSIS_DIR}/m1"
export M2_DIR="${ANALYSIS_DIR}/m2"
export PN_DIR="${ANALYSIS_DIR}/pn"
export MASK_DIR="${ANALYSIS_DIR}/mask"
export IMAGE_DIR="${ANALYSIS_DIR}/images"
export SUBTRACTION_DIR="${ANALYSIS_DIR}/subtracted"
export CONFIG_DIR="${ANALYSIS_DIR}/config"
export REGION_SRC_DIR="${ANALYSIS_DIR}/reg/src"
export REGION_BKG_DIR="${ANALYSIS_DIR}/reg/bkg"
export QA_DIR="${ANALYSIS_DIR}/QA"
export LOG_DIR="${QA_DIR}/logs"

export BLANK_SKY_DIR="${BASE_DIR}/blank_sky_files/vignette"
export OLD_FILES_DIR="${ANALYSIS_DIR}/old_files"

# -- Script helpers --
export CREATE_EVENTS_SH="${SCRIPTS_DIR}/create_events.sh"
export LIGHT_CURVES_SH="${SCRIPTS_DIR}/light_curves.sh"
export FILTER_FLARES_SH="${SCRIPTS_DIR}/filter_flares.sh"
export MAKE_CHEESE_SH="${SCRIPTS_DIR}/make_cheese.sh"
export MAKE_IMAGES_SH="${SCRIPTS_DIR}/make_images.sh"
export MAKE_REGIONS_SH="${SCRIPTS_DIR}/make_regions.sh"
export RUN_XSPEC_SH="${SCRIPTS_DIR}/run_xspec.sh"
export DOUBLE_SUBTRACTION_SH="${SCRIPTS_DIR}/double_subtraction.sh"
export SET_SAS_VARIABLES_SH="${SCRIPTS_DIR}/set_SAS_variables.sh"
export RUN_ALL_SH="${ANALYSIS_DIR}/run_all.sh"
export RESOLVE_PATHS_SH="${SCRIPTS_DIR}/resolve_paths.sh"

# -- Config Files --

export RATES_ENV_FILE="${CONFIG_DIR}/rates.env"
export REGIONS_ENV_FILE="${CONFIG_DIR}/regions.env"
export CCDS_ENV_FILE="${CONFIG_DIR}/ccds.env"
export SPECTRA_ENV_FILE="${CONFIG_DIR}/spectra.env"

# -- Project Files --

export MOS1_S001_FITS="${ANALYSIS_DIR}/mos1S001.fits"
export MOS2_S002_FITS="${ANALYSIS_DIR}/mos2S002.fits"
export PN_S003_FITS="${ANALYSIS_DIR}/pnS003.fits"
export PN_S003_OOT_FITS="${ANALYSIS_DIR}/pnS003-oot.fits"


# ------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------
log "Resolved paths for OBS_ID=${OBS_ID}"
if [[ "$SAS_VERBOSE_LEVEL" -ge 2 ]]; then
  log "Resolved paths:"
  declare -p BASE_DIR OBS_ID SCRIPTS_DIR OBS_DIR ODF_DIR ANALYSIS_DIR \
    TEMPLATE_DIR M1_DIR M2_DIR PN_DIR MASK_DIR IMAGE_DIR SUBTRACTION_DIR CONFIG_DIR \
    REGION_SRC_DIR REGION_BKG_DIR LOG_DIR QA_DIR BLANK_SKY_DIR OLD_FILES_DIR \
    CREATE_EVENTS_SH LIGHT_CURVES_SH FILTER_FLARES_SH MAKE_CHEESE_SH MAKE_IMAGES_SH \
    MAKE_REGIONS_SH RUN_XSPEC_SH DOUBLE_SUBTRACTION_SH SET_SAS_VARIABLES_SH RUN_ALL_SH \
    RATES_ENV_FILE REGIONS_ENV_FILE CCDS_ENV_FILE SPECTRA_ENV_FILE \
    MOS1_S001_FITS MOS2_S002_FITS PN_S003_FITS PN_S003_OOT_FITS \
    RESOLVE_PATHS_SH \
  | sed 's/^declare -x/export/' \
  | while IFS= read -r line; do
      log_info "$line"
    done

fi

pop_tag "$TAG"