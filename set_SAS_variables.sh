#!/usr/bin/env bash
#########################################################################################################
# set_SAS_variables.sh
#   Initialise HEASoft + XMM-SAS for one observation and (optionally) build
#   the CIF/ODF calibration files.
#
# Usage:
#   ./set_SAS_variables.sh --obs-id <ID> [--build-ccf yes|no] [--run-sasversion yes|no] [--verbose <level>]
#
# Example:
#   ./set_SAS_variables.sh --obs-id 0922150101 --build-ccf no --run-sasversion no
#########################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
# set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_set_SAS='[set_SAS]'
push_tag "$TAG_set_SAS"
VERBOSITY_DEFAULT="${SAS_VERBOSE_LEVEL:-errors}"
verbose_level "$VERBOSITY_DEFAULT"




# ------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------
OBS_ID_DEFAULT=""
BUILD_DEFAULT="no"
RUN_SASVERSION_DEFAULT="no"



# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") --obs-id <id> [options]

Options:
  --obs-id          <id>        Observation ID (e.g., 0881900301) [required]
  --build-ccf      <yes|no>     Build CCF files                              [default: $BUILD_DEFAULT]
  --run-sasversion <yes|no>     Run sasversion                               [default: $RUN_SASVERSION_DEFAULT]
  --verbose         <level>     Verbosity: none|errors|all|0|1|2|yes|no      [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose                Enable verbose SAS output
  -h, --help                    Show help
EOF
}




# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --build-ccf)          BUILD_FLAG="$(norm_flag "$2")";        shift 2;;
    --run-sasversion)     RUN_SASVERSION="$(norm_flag "$2")";    shift 2;;
    --verbose)            if [[ -n "${2-}" && $2 != -* ]]; then
                          verbose_level "$2";                    shift 2; else
                          verbose_level all;                     shift  ; fi ;;
    -v)                   verbose_level all;                     shift ;;
    -h|--help)            usage;                                 exit 0;;
    *)                    echo "Unknown arg: $1"; usage;    exit 1;;
  esac
done


# Use defaults if not provided
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BUILD_FLAG="${BUILD_FLAG:-$BUILD_DEFAULT}"
RUN_SASVERSION="${RUN_SASVERSION:-$RUN_SASVERSION_DEFAULT}"

# Sanity checks
[[ -n "$OBS_ID" ]] || { log "No OBS_ID specified"; usage; exit 1; }




# ------------------------------------------------------------------------
# Set SAS/ HEADAS path variables and initialize
# ------------------------------------------------------------------------
# -- User Paths -- (can overide with env so make sure your env is correct)
log "Setting env paths..."
HEADAS=${HEADAS:-$HOME/opt/heasoft-6.35.1/x86_64-apple-darwin22.6.0}
SAS_DIR=${SAS_DIR:-$HOME/opt/sas/xmmsas_22.1.0-a8f2c2afa-20250303}
SAS_CCFPATH=${SAS_CCFPATH:-$HOME/opt/sas/ccf}
BASE_ODF_DIR=${BASE_ODF_DIR:-$HOME/Desktop/Wittman_Research/XSorter/XMM/observation_data}


# -- Export Variables --
log "Exporting variables..."
export HEADAS
export SAS_DIR
export SAS_CCFPATH
export OBS_ID
export SAS_ODF="$BASE_ODF_DIR/$OBS_ID/odf"

# -- Initialize --
log "Initializing SAS..."
set +u
run_verbose ". \"$HEADAS/headas-init.sh\""
run_verbose ". \"$SAS_DIR/setsas.sh\""
set -u

# Change to the specified directory
cd "$SAS_ODF"

# -- Build calibration/ odf --
if [ "$BUILD_FLAG" = "yes" ]; then
    # require cifbuild
    # require odfingest

    log "Building calibration files..."
    run_verbose cifbuild # Build the calibration files

    export SAS_CCF="$(pwd)/ccf.cif" # Set the SAS_CCF before odfingest
    log "Running odfingest..."
    run_verbose odfingest
fi

# (Re)set the SAS_CCF environment variable
export SAS_CCF="$(pwd)/ccf.cif"

# Set the SAS_ODF environment variable
export SAS_ODF="$(pwd)/$(ls -1 *SUM.SAS)"

if [ "$RUN_SASVERSION" = "yes" ]; then
     run_verbose sasversion
fi

log "SAS environment set for OBS_ID=$OBS_ID"
if [ "$SAS_VERBOSE_LEVEL" -ge 2 ]; then
  log "SAS environment variables:"
  declare -p HEADAS SAS_DIR SAS_CCFPATH OBS_ID SAS_ODF SAS_CCF | sed 's/^declare -x/export/' \
  | while IFS= read -r line; do
      log_info "$line"
    done
fi
pop_tag "$TAG_set_SAS"
