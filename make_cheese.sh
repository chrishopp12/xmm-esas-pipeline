#!/usr/bin/env bash
###############################################################################
# Script Name : make_cheese.sh
# Description : Runs "cheese" masking and mask creation.
#
# Usage:
#   ./make_cheese.sh [options]
#
# Example:
#   ./make_cheese.sh --with-cheese yes --verbose 2
#
# Arguments:
#   --obs-id        <id>            Observation ID [required]
#   --base-dir      <path>          Base dir with /scripts and /observation_data
#   --det-ml        <float>         Minimum detection likelihood                  [default: 15]
#   --flux-min      <float>         Minimum flux in erg/cm^2/s                    [default: 1e-14]
#   --id-band       <int>           ID_BAND for detector selection, 0 for summary [default: 0]
#   --ext-ml-max    <float>         Maximum extension likelihood                  [default: 1]
#   --bkgfraction   <float>         Background fraction for cheese mask creation  [default: 0.5]
#   --with-cheese   <yes|no>        Whether to use cheese                         [default: no]
#   --emin          <float>         Cheese minimum energy                         [default: 400]
#   --emax          <float>         Cheese maximum energy                         [default: 7200]
#   --cheese-scale  <float>         Cheese scale factor                           [default: 0.5]
#   --cheese-rate   <float>         Cheese rate                                   [default: 1.0]
#   --dist-NN       <float>         Distance for nearest neighbor                 [default: 40.0]
#   --verbose                       Verbosity: none|errors|all|0|1|2|yes|no       [default: errors]
#   -v | --verbose                  Enable verbose SAS output
#   -h | --help                     Show help
#
# Notes:
#   - Typicially, you will only run --with-cheese true for the initial emllist generation
#   - Default parameters find a LOT of sources, edit emllist accordingly
###############################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_make_cheese='[make_cheese]'
push_tag "$TAG_make_cheese"
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
WITH_CHEESE_DEFAULT="no"
DET_ML_DEFAULT=15
FLUX_MIN_DEFAULT=1e-14
ID_BAND_DEFAULT=0
EXT_ML_MAX_DEFAULT=1
BKGFRAC_DEFAULT=0.5
EMIN_DEFAULT=400
EMAX_DEFAULT=7200
CHEESE_SCALE_DEFAULT=0.5
CHEESE_RATE_DEFAULT=1.0
DIST_NN_DEFAULT=40.0


# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") --obs-id <id> --base-dir <path> [--verbose <level>]

Options:
  --obs-id        <id>        Observation ID (e.g., 0881900301) [required]
  --base-dir      <path>      Base dir with /scripts and /blank_all
  --det-ml        <float>     Minimum detection likelihood                  [default: ${DET_ML_DEFAULT}]
  --flux-min      <float>     Minimum flux in erg/cm^2/s                    [default: ${FLUX_MIN_DEFAULT}]
  --id-band       <int>       ID_BAND for detector selection, 0 for summary [default: ${ID_BAND_DEFAULT}]
  --ext-ml-max    <float>     Maximum extension likelihood                  [default: ${EXT_ML_MAX_DEFAULT}]
  --bkgfraction   <float>     Background fraction for cheese mask creation  [default: ${BKGFRAC_DEFAULT}]
  --with-cheese   <yes|no>    Whether to use cheese                         [default: ${WITH_CHEESE_DEFAULT}]
  --emin          <float>     Cheese minimum energy                         [default: ${EMIN_DEFAULT}]
  --emax          <float>     Cheese maximum energy                         [default: ${EMAX_DEFAULT}]
  --cheese-scale  <float>     Cheese scale factor                           [default: ${CHEESE_SCALE_DEFAULT}]
  --cheese-rate   <float>     Cheese rate                                   [default: ${CHEESE_RATE_DEFAULT}]
  --dist-NN       <float>     Distance for nearest neighbor                 [default: ${DIST_NN_DEFAULT}]
  --verbose       <level>     Verbosity: none|errors|all|0|1|2|yes|no       [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose              Enable verbose SAS output
  -h | --help                 Show help
EOF
}

# -------------------------
# CLI parsing
# -------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

# -- Reset others to defaults --
WITH_CHEESE="${WITH_CHEESE_DEFAULT}"
DET_ML="${DET_ML_DEFAULT}"
FLUX_MIN="${FLUX_MIN_DEFAULT}"
ID_BAND="${ID_BAND_DEFAULT}"
EXT_ML_MAX="${EXT_ML_MAX_DEFAULT}"
BKGFRACTION="${BKGFRAC_DEFAULT}"
EMIN="${EMIN_DEFAULT}"
EMAX="${EMAX_DEFAULT}"
CHEESE_SCALE="${CHEESE_SCALE_DEFAULT}"
CHEESE_RATE="${CHEESE_RATE_DEFAULT}"  
DIST_NN="${DIST_NN_DEFAULT}"



while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --det-ml)             DET_ML="$2";                           shift 2;;
    --flux-min)           FLUX_MIN="$2";                         shift 2;;
    --id-band)            ID_BAND="$2";                          shift 2;;
    --ext-ml-max)         EXT_ML_MAX="$2";                       shift 2;;
    --bkgfraction)        BKGFRACTION="$2";                          shift 2;;
    --with-cheese)        WITH_CHEESE="$(norm_flag "$2")";       shift 2;;
    --emin)               EMIN="$2";                             shift 2;;
    --emax)               EMAX="$2";                             shift 2;;
    --cheese-scale)       CHEESE_SCALE="$2";                     shift 2;;
    --cheese-rate)        CHEESE_RATE="$2";                      shift 2;;
    --dist-nn)            DIST_NN="$2";                          shift 2;;
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




# ------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------
log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  WITH_CHEESE    = ${WITH_CHEESE}"
log "  DET_ML         = ${DET_ML}"
log "  FLUX_MIN       = ${FLUX_MIN}"
log "  ID_BAND        = ${ID_BAND}"
log "  EXT_ML_MAX     = ${EXT_ML_MAX}"
log "  BKGFRACTION    = ${BKGFRACTION}"
log "  EMIN           = ${EMIN}"
log "  EMAX           = ${EMAX}"
log "  CHEESE_SCALE   = ${CHEESE_SCALE}"
log "  CHEESE_RATE    = ${CHEESE_RATE}"
log "  DIST_NN        = ${DIST_NN}"
log ""




# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"

# Sanity check required files and scripts
[[ -d "$MASK_DIR" ]] || die "Mask directory not found: $MASK_DIR"


# ------------------------------------------------------------------------
# Run Cheese and Make Masks
# ------------------------------------------------------------------------
require cheese
require region
require makemask

# -- Initial Cheese --
if [[ "$WITH_CHEESE" == "yes" ]]; then
  log "Running cheese with parameters:"
    log "  - emin: ${EMIN:-}"
    log "  - emax: ${EMAX:-}"
    log "  - scale: ${CHEESE_SCALE:-}"
    log "  - rate: ${CHEESE_RATE:-}"
    log "  - dist: ${DIST_NN:-}"
  
  run_verbose "cheese mos1file='$MASK_DIR/mos1S001-allevc.fits' mos2file='$MASK_DIR/mos2S002-allevc.fits' pnfile='$MASK_DIR/pnS003-allevc.fits' pnootfile='$MASK_DIR/pnS003-allevcoot.fits' elowlist=$EMIN ehighlist=$EMAX scale=$CHEESE_SCALE ratetotal=$CHEESE_RATE dist=$DIST_NN keepinterfiles=no"
fi

# -- Create masks --
log "Making masks with parameters:"
log "  - det-ml: ${DET_ML:-}"
log "  - flux-min: ${FLUX_MIN:-}"
log "  - id-band: ${ID_BAND:-}"
log "  - ext-ml-max: ${EXT_ML_MAX:-}"
log "  - bkgfraction: ${BKGFRACTION:-}"

EXP="(DET_ML >= $DET_ML)&&(ID_INST == 0)&&(FLUX >= $FLUX_MIN)&&(ID_BAND == $ID_BAND)&&(EXT_ML<=$EXT_ML_MAX)"
log "Using expression: $EXP; bkgfraction=$BKGFRACTION"

log "Creating masks for MOS1..."
run_verbose "region eventset='$MASK_DIR/mos1S001-allevc.fits' operationstyle=global srclisttab=emllist.fits:SRCLIST expression=\"$EXP\" bkgregionset=mos1S001-bkgregtdet.fits radiusstyle=contour nosrcellipse=no bkgfraction=$BKGFRACTION outunit=detxy verbosity=1"
run_verbose "region eventset='$MASK_DIR/mos1S001-allevc.fits' operationstyle=global srclisttab=emllist.fits:SRCLIST expression=\"$EXP\" bkgregionset=mos1S001-bkgregtsky.fits radiusstyle=contour nosrcellipse=no bkgfraction=$BKGFRACTION outunit=xy verbosity=1"
run_verbose "makemask imagefile=mos1S001-fovimt.fits maskfile=mos1S001-fovimtmask.fits regionfile=mos1S001-bkgregtsky.fits cheesefile=mos1S001-cheese2.fits"

log "Creating masks for MOS2..."
run_verbose "region eventset='$MASK_DIR/mos2S002-allevc.fits' operationstyle=global srclisttab=emllist.fits:SRCLIST expression=\"$EXP\" bkgregionset=mos2S002-bkgregtdet.fits radiusstyle=contour nosrcellipse=no bkgfraction=$BKGFRACTION outunit=detxy verbosity=1"
run_verbose "region eventset='$MASK_DIR/mos2S002-allevc.fits' operationstyle=global srclisttab=emllist.fits:SRCLIST expression=\"$EXP\" bkgregionset=mos2S002-bkgregtsky.fits radiusstyle=contour nosrcellipse=no bkgfraction=$BKGFRACTION outunit=xy verbosity=1"
run_verbose "makemask imagefile=mos2S002-fovimt.fits maskfile=mos2S002-fovimtmask.fits regionfile=mos2S002-bkgregtsky.fits cheesefile=mos2S002-cheese2.fits"

log "Creating masks for PN..."
run_verbose "region eventset='$MASK_DIR/pnS003-allevc.fits' operationstyle=global srclisttab=emllist.fits:SRCLIST expression=\"$EXP\" bkgregionset=pnS003-bkgregtdet.fits radiusstyle=contour nosrcellipse=no bkgfraction=$BKGFRACTION outunit=detxy verbosity=1"
run_verbose "region eventset='$MASK_DIR/pnS003-allevc.fits' operationstyle=global srclisttab=emllist.fits:SRCLIST expression=\"$EXP\" bkgregionset=pnS003-bkgregtsky.fits radiusstyle=contour nosrcellipse=no bkgfraction=$BKGFRACTION outunit=xy verbosity=1"
run_verbose "makemask imagefile=pnS003-fovimt.fits maskfile=pnS003-fovimtmask.fits regionfile=pnS003-bkgregtsky.fits cheesefile=pnS003-cheese2.fits"

# -- Rename cheese files --
log "Renaming cheese files..."
mv mos1S001-cheeset.fits mos1S001-cheese_old.fits || true
mv mos1S001-cheese2.fits mos1S001-cheeset.fits || true
mv mos2S002-cheeset.fits mos2S002-cheese_old.fits || true
mv mos2S002-cheese2.fits mos2S002-cheeset.fits || true
mv pnS003-cheeset.fits pnS003-cheese_old.fits   || true
mv pnS003-cheese2.fits pnS003-cheeset.fits     || true

log "Cheese masks created successfully."

pop_tag "$TAG_make_cheese"