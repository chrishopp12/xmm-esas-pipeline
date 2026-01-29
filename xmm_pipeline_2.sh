#!/usr/bin/env bash

###########################################################################################################
# Script Name : xmm_pipeline_2.sh
# Description : Stage 2 of the XMM ESAS pipeline.
#               - Runs ESAS 'cheese' to make initial masks & FOV images
#               - Builds per-detector background region masks via step3.sh
#               - Fills emllist.fits with emlfill and reruns step3.sh
#               - (Optional) Opens DS9 to review masks
#
# Usage examples:
#   ./xmm_pipeline_2.sh --obs-id 0881900301
#   ./xmm_pipeline_2.sh --obs-id 0881900301 --create-files yes
#
# Assumptions:
#   - Stage 1 (or equivalent) preferred, but not necessary.
#   - ESAS tasks ('cheese', 'emlfill', 'region', 'makemask') are available.
#   - scripts/step1.sh and scripts/step3.sh exist.
#
# Arguments:
#   --obs-id        <id>       Observation ID [required]
#   --base-dir      <path>     Base dir containing /scripts and /observation_data
#   --create-files  <yes|no>   Create event files                                  [default: no]
#   --fill          <yes|no>   Fill NULL summary entries in emllist                [default: yes]
#   --with-cheese   <yes|no>   Whether to run cheese                               [default: yes]
#   --det-ml        <float>    Minimum detection likelihood                        [default: 15]    in cheese
#   --flux-min      <float>    Minimum flux in erg/cm^2/s                          [default: 1e-14] in cheese
#   --id-band       <int>      ID_BAND for detector selection, 0 for summary       [default: 0]     in cheese
#   --ext-ml-max    <float>    Maximum extension likelihood                        [default: 1]     in cheese
#   --bkgfraction   <float>    Background fraction for cheese mask creation        [default: 0.5]   in cheese
#   --emin          <float>    Cheese minimum energy in eV                         [default: 400]   in cheese
#   --emax          <float>    Cheese maximum energy in eV                         [default: 7200]  in cheese
#   --cheese-scale  <float>    Cheese scale factor                                 [default: 0.5]   in cheese
#   --cheese-rate   <float>    Cheese rate                                         [default: 1.0]   in cheese 
#   --dist-NN       <float>    Distance for nearest neighbor                       [default: 40.0]  in cheese
#   --open-ds9      yes|no     Open DS9 on the cheese & FOV images                 [default: yes]
#   --verbose                  Verbosity: none|errors|all|0|1|2|yes|no             [default: errors]
#   -v | --verbose             Enable verbose SAS output
#   -h | --help                Show help
###########################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

LOG_TAG='[STAGE 2]'
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

CREATE_FILES_DEFAULT="no"
FILL_DEFAULT="yes"
WITH_CHEESE_DEFAULT="yes"
OPEN_DS9_DEFAULT="yes"


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
  --create-files    <yes|no>    Create event files                            [default: ${CREATE_FILES_DEFAULT}]
  --fill            <yes|no>    Fill NULL summary entries in emllist          [default: ${FILL_DEFAULT}]
  --with-cheese     <yes|no>    Whether to run cheese                         [default: ${WITH_CHEESE_DEFAULT}]
  --det-ml          <float>     Minimum detection likelihood                  [default: 15]    in cheese
  --flux-min        <float>     Minimum flux in erg/cm^2/s                    [default: 1e-14] in cheese
  --id-band         <int>       ID_BAND for detector selection, 0 for summary [default: 0]     in cheese
  --ext-ml-max      <float>     Maximum extension likelihood                  [default: 1]     in cheese
  --bkgfraction     <float>     Background fraction for cheese mask creation  [default: 0.5]   in cheese
  --emin            <float>     Cheese minimum energy                         [default: 400]   in cheese
  --emax            <float>     Cheese maximum energy                         [default: 7200]  in cheese
  --cheese-scale    <float>     Cheese scale factor                           [default: 0.5]   in cheese
  --cheese-rate     <float>     Cheese rate                                   [default: 1.0]   in cheese
  --dist-nn         <float>     Distance for nearest neighbor                 [default: 40.0]  in cheese
  --open-ds9        <yes|no>    Open DS9 to review masks                      [default: ${OPEN_DS9_DEFAULT}]
  --verbose         <level>     Verbosity: none|errors|all|0|1|2|yes|no       [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose                Enable verbose SAS output
  -h, --help                    Show help
EOF
}


# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

# -- Reset others to defaults --
CREATE_FILES="${CREATE_FILES_DEFAULT}"
FILL="${FILL_DEFAULT}"
WITH_CHEESE="${WITH_CHEESE_DEFAULT}"
OPEN_DS9="${OPEN_DS9_DEFAULT}"

# Cheese script handles all other defaults

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                            shift 2;;
    --base-dir)           BASE_DIR="$2";                          shift 2;;
    --create-files)       CREATE_FILES="$(norm_flag "$2")";       shift 2;;
    --fill)               FILL="$(norm_flag "$2")";               shift 2;;
    --with-cheese)        WITH_CHEESE="$(norm_flag "$2")";        shift 2;;
    --det-ml)             DET_ML="$2";                            shift 2;;
    --flux-min)           FLUX_MIN="$2";                          shift 2;;
    --id-band)            ID_BAND="$2";                           shift 2;;
    --ext-ml-max)         EXT_ML_MAX="$2";                        shift 2;;
    --bkgfraction)        BKGFRACTION="$2";                       shift 2;;
    --emin)               EMIN="$2";                              shift 2;;
    --emax)               EMAX="$2";                              shift 2;;
    --cheese-scale)       CHEESE_SCALE="$2";                      shift 2;;
    --cheese-rate)        CHEESE_RATE="$2";                       shift 2;;
    --dist-nn)            DIST_NN="$2";                           shift 2;;
    --open-ds9)           OPEN_DS9="$(norm_flag "$2")";           shift 2;;
    --verbose)            if [[ -n "${2-}" && $2 != -* ]]; then
                          verbose_level "$2";                     shift 2; else
                          verbose_level all;                      shift  ; fi ;;
    -v)                   verbose_level all;                      shift ;;
    -h|--help)      usage; exit 0;;
    *)              log "Unknown arg: $1"; usage; exit 1;;
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

LOG_FILE="${LOG_DIR}/xmm_pipeline_2_${OBS_ID}_$(date +%Y%m%d_%H%M%S).log"
export LOG_FILE
log "*************************************************"
log "Logging to: ${LOG_FILE#$BASE_DIR/}"
log "*************************************************"

log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  OBS_ID         = ${OBS_ID}"
log "  BASE_DIR       = ${BASE_DIR}"
log "  CREATE_FILES   = ${CREATE_FILES}"
log "  FILL           = ${FILL}"
log "  WITH_CHEESE    = ${WITH_CHEESE}"
log "  DET_ML         = ${DET_ML:-}"
log "  FLUX_MIN       = ${FLUX_MIN:-}"
log "  ID_BAND        = ${ID_BAND:-}"
log "  EXT_ML_MAX     = ${EXT_ML_MAX:-}"
log "  BKGFRACTION    = ${BKGFRACTION:-}"
log "  EMIN           = ${EMIN:-}"
log "  EMAX           = ${EMAX:-}"
log "  CHEESE_SCALE   = ${CHEESE_SCALE:-}"
log "  CHEESE_RATE    = ${CHEESE_RATE:-}"
log "  DIST_NN        = ${DIST_NN:-}"
log "  OPEN_DS9       = ${OPEN_DS9}"
log ""



# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"


# Sanity check required files and scripts
[[ -d "$ANALYSIS_DIR" ]] || die "Analysis dir not found: $ANALYSIS_DIR"
[[ -d "$SCRIPTS_DIR"  ]] || die "Scripts dir not found: $SCRIPTS_DIR"
[[ -d "$MASK_DIR"     ]] || { log "Creating mask dir: $MASK_DIR"; mkdir -p "$MASK_DIR"; }
[[ -f "$CREATE_EVENTS_SH"        ]] || die "create_events.sh script not found: $CREATE_EVENTS_SH"
[[ -f "$MAKE_CHEESE_SH"        ]] || die "make_cheese.sh script not found: $MAKE_CHEESE_SH"
[[ -f "$SET_SAS_VARIABLES_SH"      ]] || die "SAS init script not found: $SET_SAS_VARIABLES_SH"




# ------------------------------------------------------------------------
# Stage 2.0: Initialize SAS and HEASoft
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 2.0: Initialize SAS and HEASoft"
log "-------------------------------------------------"
log "Sourcing SAS variables (build=false) from: $SET_SAS_VARIABLES_SH"

source "$SET_SAS_VARIABLES_SH" --obs-id "$OBS_ID" --build-ccf false --run-sasversion false --verbose "$SAS_VERBOSE_LEVEL"

# Check SAS loaded properly
if ! command -v sasversion >/dev/null 2>&1; then
  die "sasversion not in PATH after sourcing. Check $SET_SAS_VARIABLES_SH"
fi




# ------------------------------------------------------------------------
# Stage 2.1: Run create_events.sh to produce source files
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 2.1: Run create_events.sh to produce source files"
log "-------------------------------------------------"

cd "$MASK_DIR"


if [[ "$CREATE_FILES" == "yes" ]]; then
    log "Running create_events.sh to create event files in mask/…"
    bash "$CREATE_EVENTS_SH" --directory "$MASK_DIR" --run-filter yes --run-chains yes --verbose "$SAS_VERBOSE_LEVEL"
else
    log "Skipping create_events.sh (create-files=no)."
fi


log "Confirming event files exist in mask/…"
for f in mos1S001-allevc.fits mos2S002-allevc.fits pnS003-allevc.fits; do
    if [[ ! -f "$f" ]]; then
        die "Missing required event file: $MASK_DIR/$f"
    fi
done
log "All required event files found."




# ------------------------------------------------------------------------
# Stage 2.2 Initial cheese run [optional]
# Notes:
#  - Produces cheese masks and emllist.fits
#  - emllist is NOT filled
#  - All standard parameters can be set via CLI
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 2.2: Initial cheese run"
log "-------------------------------------------------"

if [[ "$WITH_CHEESE" == "yes" ]]; then   
    
    log "Running cheese..."


    args=()
    [[ -n "${DET_ML:-}"        ]] && args+=( --det-ml        "$DET_ML" )
    [[ -n "${FLUX_MIN:-}"      ]] && args+=( --flux-min      "$FLUX_MIN" )
    [[ -n "${ID_BAND:-}"       ]] && args+=( --id-band       "$ID_BAND" )
    [[ -n "${EXT_ML_MAX:-}"    ]] && args+=( --ext-ml-max    "$EXT_ML_MAX" )
    [[ -n "${BKGFRACTION:-}"   ]] && args+=( --bkgfraction   "$BKGFRACTION" )
    [[ -n "${EMIN:-}"          ]] && args+=( --emin          "$EMIN" )
    [[ -n "${EMAX:-}"          ]] && args+=( --emax          "$EMAX" )
    [[ -n "${CHEESE_SCALE:-}"  ]] && args+=( --cheese-scale  "$CHEESE_SCALE" )
    [[ -n "${CHEESE_RATE:-}"   ]] && args+=( --cheese-rate   "$CHEESE_RATE" )
    [[ -n "${DIST_NN:-}"       ]] && args+=( --dist-nn       "$DIST_NN" )
    [[ -n "${SAS_VERBOSE_LEVEL:-}" ]] && args+=( --verbose   "$SAS_VERBOSE_LEVEL" )

    args+=( --with-cheese yes )

    bash "$MAKE_CHEESE_SH" "${args[@]}" # Runs only wiith parameters set by CLI, lets cheese handle defaults
fi





# ------------------------------------------------------------------------
# Stage 2.3: Fill emllist [optional]
# Notes:
#  - Fills NULL summary entries in emllist
#  - emllist will likely require additional editing
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 2.3: Fill emllist"
log "-------------------------------------------------"

if [[ "$FILL" == "yes" ]]; then
  require emlfill

  ts="$(date -u +"%Y%m%dT%H%M%SZ")"

  log "Filling emllist (backup: emllist_${ts}.old)…"
  [[ -f emllist.fits ]] || die "emllist.fits not found after cheese — cannot run emlfill."
  cp -f emllist.fits "emllist_${ts}.old"

  emlfill emlin="emllist_${ts}.old" emlout=emllist.fits
else
  log "Skipping emllist fill (fill=no)."
fi





# ------------------------------------------------------------------------
# Stage 2.4: Second pass mask construction after emlfill
# Notes:
#  - This stage refines the masks based on the filled emllist
#  - To manually edit: fv emllist.fits
#  - Run step3.sh --with-cheese no after editing OR
#  - xmm_pipeline_2.sh --fill no --with-cheese no
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 2.4: Second pass mask construction after emlfill"
log "-------------------------------------------------"
log "Second pass mask/region build via step3.sh (post-emlfill)…"
log "Masks created with parameters:"
    log "  - det-ml: ${DET_ML:-}"
    log "  - flux-min: ${FLUX_MIN:-}"
    log "  - id-band: ${ID_BAND:-}"
    log "  - ext-ml-max: ${EXT_ML_MAX:-}"
    log "  - bkgfraction: ${BKGFRACTION:-}"

args=()
[[ -n "${DET_ML:-}"       ]] && args+=( --det-ml      "$DET_ML" )
[[ -n "${FLUX_MIN:-}"     ]] && args+=( --flux-min    "$FLUX_MIN" )
[[ -n "${ID_BAND:-}"      ]] && args+=( --id-band     "$ID_BAND" )
[[ -n "${EXT_ML_MAX:-}"   ]] && args+=( --ext-ml-max  "$EXT_ML_MAX" )
[[ -n "${BKGFRACTION:-}"  ]] && args+=( --bkgfraction "$BKGFRACTION" )

args+=( --with-cheese no )
args+=( --verbose "$SAS_VERBOSE_LEVEL" )

bash "$MAKE_CHEESE_SH" "${args[@]}"




# ------------------------------------------------------------------------
# Stage 2.5: View masks
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 2.5: View masks"
log "-------------------------------------------------"

if [[ "$OPEN_DS9" == "yes" ]]; then
  require ds9
  log "Opening DS9 to review cheese & FOV images (background)…"

    if [[ "$(uname)" == "Darwin" ]]; then
        DS9_BIN="/Applications/SAOImageDS9.app/Contents/MacOS/ds9"
    else
        DS9_BIN="ds9"
    fi

    "$DS9_BIN" "$MASK_DIR"/mos1S001-cheeset.fits "$MASK_DIR"/mos1S001-fovimt.fits &
    "$DS9_BIN" "$MASK_DIR"/mos2S002-cheeset.fits "$MASK_DIR"/mos2S002-fovimt.fits &
    "$DS9_BIN" "$MASK_DIR"/pnS003-cheeset.fits  "$MASK_DIR"/pnS003-fovimt.fits  &
fi




# ------------------------------------------------------------------------
# Stage 2.6: Transfer files
# ------------------------------------------------------------------------
log "-------------------------------------------------"
log "Stage 2.6: Transfer files"
log "-------------------------------------------------"

cd "$ANALYSIS_DIR"
log "Copying files to m1/ m2/ pn/ …"
mkdir -p m1 m2 pn

cp -f \
  "$ANALYSIS_DIR"/mos1S001-allevc.fits "$ANALYSIS_DIR"/mos1S001-gti.fits "$ANALYSIS_DIR"/ratem1.fits "$ANALYSIS_DIR"/mos1S001.fits "$ANALYSIS_DIR"/mos1S001-allimc.fits \
  "$MASK_DIR"/mos1S001-bkgregtdet.fits \
  "$M1_DIR"

cp -f \
  "$ANALYSIS_DIR"/mos2S002-allevc.fits "$ANALYSIS_DIR"/mos2S002-gti.fits "$ANALYSIS_DIR"/ratem2.fits "$ANALYSIS_DIR"/mos2S002.fits "$ANALYSIS_DIR"/mos2S002-allimc.fits \
  "$MASK_DIR"/mos2S002-bkgregtdet.fits \
  "$M2_DIR"

cp -f \
  "$ANALYSIS_DIR"/pnS003-allevc.fits "$ANALYSIS_DIR"/pnS003-gti.fits "$ANALYSIS_DIR"/ratepn.fits "$ANALYSIS_DIR"/pnS003.fits "$ANALYSIS_DIR"/pnS003-allimc.fits \
  "$MASK_DIR"/pnS003-bkgregtdet.fits \
  "$PN_DIR"



log "Stage 2 complete. To further refine masks, edit emllist.fits and re-run step3.sh --with-cheese no."
