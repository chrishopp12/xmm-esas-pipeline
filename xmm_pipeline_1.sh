#!/usr/bin/env bash

#############################################################################################################
# Script Name : xmm_pipeline_1.sh
# Description : Stage 1 of the XMM ESAS pipeline.
#
#               - Clones blank workspace (blank_all -> observation_data/<obs_id>)
#               - Initializes SAS/HEASoft using scripts/set_SAS_variables.sh
#               - Optionally fetches ODFs with `startsas`
#               - Optionally runs `emchain`, `epchain`, and PN OOT correction
#               - Normalizes event file names in analysis/:
#                   mos1S001.fits, mos2S002.fits, pnS003.fits, pnS003-oot.fits (if present)
#               - Generates light curves via step2_1.sh and displays dsplot windows
#               - Prompts user for flare thresholds and writes ../config/rates.env
#               - Saves QA PNGs of full and cropped light curves
#
# Usage Examples:
#   ./xmm_pipeline_1.sh --obs-id 0881900301
#   ./xmm_pipeline_1.sh --obs-id 0881900301 --use-startsas yes
#   ./xmm_pipeline_1.sh --obs-id 0881900301 --create-dirs no --build-ccf yes
#
# Assumptions:
#   - Base directory contains ./scripts and ./blank_all
#   - ./scripts/set_SAS_variables.sh exists and configures SAS/HEASoft + CCF
#   - CCF location is handled within set_SAS_variables.sh
#
# Arguments:
#   --obs-id             <id>       Observation ID [required]
#   --base-dir           <path>     Base dir with /scripts and /observation_data
#   --create-dirs        <yes|no>   Clone blank_all to new workspace            [default: no]
#   --use-startsas       <yes|no>   Run startsas to fetch ODFs                  [default: no]
#   --build-ccf          <yes|no>   Run cifbuild/ccf_ingest                     [default: yes]
#   --run-chains         <yes|no>   Run emchain, epchain, and PN OOT            [default: yes]
#   --verbose                       Verbosity: none|errors|all|0|1|2|yes|no     [default: errors]
#   -v | --verbose                  Enable verbose SAS output
#   -h | --help                     Show help
#############################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

LOG_TAG='[STAGE 1]'
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

CREATE_DIRS_DEFAULT="no"
USE_STARTSAS_DEFAULT="no"
BUILD_CCF_DEFAULT="yes"
RUN_CHAINS_DEFAULT="yes"


# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") --obs-id <id> [options]

Options:
  --obs-id                <id>           Observation ID (e.g., 0881900301) [required]
  --base-dir              <path>         Base dir with /scripts and /blank_all
  --create-dirs           <yes|no>       Create directories from blank template      [default: ${CREATE_DIRS_DEFAULT}]
  --use-startsas          <yes|no>       Run startsas to fetch ODFs                  [default: ${USE_STARTSAS_DEFAULT}]
  --build-ccf             <yes|no>       Run cifbuild/ccf_ingest                     [default: ${BUILD_CCF_DEFAULT}]
  --run-chains            <yes|no>       Run emchain, epchain, and PN OOT            [default: ${RUN_CHAINS_DEFAULT}]
  --verbose               <level>        Verbosity: none|errors|all|0|1|2|yes|no     [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose                         Enable verbose SAS output
  -h | --help                             Show help
EOF
}


# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

# -- Reset others to defaults --
CREATE_DIRS="${CREATE_DIRS_DEFAULT}"
USE_STARTSAS="${USE_STARTSAS_DEFAULT}"
BUILD_CCF="${BUILD_CCF_DEFAULT}"
RUN_CHAINS="${RUN_CHAINS_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --create-dirs)        CREATE_DIRS="$(norm_flag "$2")";       shift 2;;
    --use-startsas)       USE_STARTSAS="$(norm_flag "$2")";      shift 2;;
    --build-ccf)          BUILD_CCF="$(norm_flag "$2")";         shift 2;;
    --run-chains)         RUN_CHAINS="$(norm_flag "$2")";        shift 2;;
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
OBS_DIR="${BASE_DIR}/observation_data/${OBS_ID}"
LOG_DIR="${OBS_DIR}/analysis/QA/logs"
LOG_FILE="${LOG_DIR}/xmm_pipeline_1_${OBS_ID}_$(date +%Y%m%d_%H%M%S).log"


if [[ -d "$OBS_DIR" ]]; then
    # Log dir exists, use standard log location from the start
    export LOG_FILE
    log "*************************************************"
    log "Logging to: ${LOG_FILE#$BASE_DIR/}"
    log "*************************************************"
else
    # OBS_DIR does not exist: use a boot log for now so we don't fail on creating the new dirs
    ORIGINAL_LOG_FILE="$LOG_FILE"
    BOOT_LOG="${BASE_DIR}/.bootstrap_log_${OBS_ID}_$$.log"
    
    export LOG_FILE="$BOOT_LOG"
    log "*************************************************"
    log "Logging to (temporary boot log): ${BOOT_LOG#$BASE_DIR/}"
    log "*************************************************"
fi

log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  OBS_ID         = ${OBS_ID}"
log "  BASE_DIR       = ${BASE_DIR}"
log "  CREATE_DIRS    = ${CREATE_DIRS}"
log "  USE_STARTSAS   = ${USE_STARTSAS}"
log "  BUILD_CCF      = ${BUILD_CCF}"
log "  RUN_CHAINS     = ${RUN_CHAINS}"
log ""


# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"

# Sanity check required files and scripts
[[ -d "$SCRIPTS_DIR" ]] || die "Scripts directory not found: $SCRIPTS_DIR"
[[ -f "$SET_SAS_VARIABLES_SH" ]] || die "SAS initialization script not found: $SET_SAS_VARIABLES_SH"
[[ -f "$LIGHT_CURVES_SH" ]] || die "Light curves script not found: $LIGHT_CURVES_SH"
[[ -f "$FILTER_FLARES_SH" ]] || die "Filter flares script not found: $FILTER_FLARES_SH"
[[ -f "$CREATE_EVENTS_SH"        ]] || die "create_events.sh script not found: $CREATE_EVENTS_SH"


# ------------------------------------------------------------------------
# Stage 1.0: Create directories
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.0: Create directories"
log "-------------------------------------------"

if [[ "$CREATE_DIRS" == "yes" ]]; then
  [[ -d "$TEMPLATE_DIR" ]] || die "Template not found: $TEMPLATE_DIR"
  [[ -e "$OBS_DIR" ]] && die "Destination already exists: $OBS_DIR"

  log "Cloning template from ${TEMPLATE_DIR#$BASE_DIR/} to ${OBS_DIR#$BASE_DIR/}"
  rsync -a "$TEMPLATE_DIR/" "$OBS_DIR/" || die "rsync failed"

  mkdir -p "$ODF_DIR" "$ANALYSIS_DIR"
else
  log "Skipping directory creation; expecting ${OBS_DIR#$BASE_DIR/} to already exist"
  [[ -d "$OBS_DIR" ]] || die "Missing observation directory: $OBS_DIR"

  # Ensure necessary subdirs exist even if workspace already exists
  mkdir -p "$ODF_DIR" "$ANALYSIS_DIR"
fi

# After directories exist, switch logging
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    # Switch over to the standard log, copy bootlog if used
    OLD_LOG_FILE="$LOG_FILE"
    LOG_FILE="${ORIGINAL_LOG_FILE}"
    export LOG_FILE

    if [[ -f "$OLD_LOG_FILE" && "$OLD_LOG_FILE" != "$LOG_FILE" ]]; then
        cat "$OLD_LOG_FILE" >> "$LOG_FILE"
        rm -f "$OLD_LOG_FILE"
        log "Boot log transferred"
        log "*************************************************"
        log "Logging to: ${LOG_FILE#$ANALYSIS_DIR/}"
        log "*************************************************"
    fi
fi


# ------------------------------------------------------------------------
# Stage 1.2: Initialize SAS and HEASoft
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.2: Initialize SAS and HEASoft"
log "-------------------------------------------"
log "Sourcing SAS variables (build=false) from: ${SET_SAS_VARIABLES_SH##*/}"

source "$SET_SAS_VARIABLES_SH" --obs-id "$OBS_ID" --build-ccf no --run-sasversion no --verbose "$SAS_VERBOSE_LEVEL"

# Check SAS loaded properly
if ! command -v sasversion >/dev/null 2>&1; then
  die "sasversion not in PATH after sourcing. Check $SET_SAS_VARIABLES_SH"
fi




# ------------------------------------------------------------------------
# Stage 1.3: startsas + ODF normalization [optional]
# Notes:
#   - startsas recovers odf tarball from XMM-Newton Archive
#   - It requires running odfingest twice, so it takes longer
#   - It also produces a .SAS file that MUST be deleted
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.3: startsas + ODF normalization"
log "-------------------------------------------"

if [[ "$USE_STARTSAS" == "yes" ]]; then
  require startsas

  log "Running startsas with odfid=${OBS_ID}, level=ODF, workdir=${OBS_DIR}"
  run_verbose "startsas odfid="${OBS_ID}" level=ODF workdir="${OBS_DIR}""

  # Flatten nested structure: move contents from odf/<obs_id>/ -> odf/
  if [[ -d "${OBS_DIR}/${OBS_ID}" ]]; then
    log "Flattening nested ODF folder: ${OBS_DIR#$BASE_DIR/}/${OBS_ID} -> ${ODF_DIR#$BASE_DIR/}"
    shopt -s dotglob nullglob
    mv "${OBS_DIR}/${OBS_ID}/"* "${ODF_DIR}/"
    rmdir "${OBS_DIR}/${OBS_ID}" 2>/dev/null || true
    shopt -u dotglob nullglob
  fi

  # Sweep stray ODF artifacts into odf/
  shopt -s nullglob
  for f in "${OBS_DIR}"/*.ASC "${OBS_DIR}"/*.TAR "${OBS_DIR}"/*.tar.gz; do
    log "Moving $(basename "$f") -> odf/"
    mv "$f" "${ODF_DIR}/"
  done
  shopt -u nullglob

  # Delete any stale SAS summary files and ccf.cif
  rm -f "${OBS_DIR}"/*.SAS "${ODF_DIR}"/*.SAS 
  rm -f "${OBS_DIR}/ccf.cif" "${ODF_DIR}/ccf.cif"


else
  log "Skipping startsas (use --use-startsas yes to enable)."
fi




# ------------------------------------------------------------------------
# Stage 1.4: build CCF/ingest [optional]
# Notes: Can be neglected after initial run
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.4: Build CCF and ingest ODF"
log "-------------------------------------------"

if [[ "$BUILD_CCF" == "yes" ]]; then
  log "Re-sourcing SAS env with build=true (cifbuild/odfingest)"
  unset SAS_CCF
  unset SAS_ODF

  source "$SET_SAS_VARIABLES_SH" --obs-id "$OBS_ID" --build-ccf yes --run-sasversion no --verbose "$SAS_VERBOSE_LEVEL"

else
  log "Skipping CCF build and ODF ingest (use --build-ccf yes to enable)."
fi

# Everything below should run from analysis/
cd "$ANALYSIS_DIR"




# ------------------------------------------------------------------------
# Stage 1.5: Chains (emchain / epchain) [optional]
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.5: Chains (emchain / epchain)"
log "-------------------------------------------"

if [[ "$RUN_CHAINS" == "yes" ]]; then
    bash "$CREATE_EVENTS_SH" --run-chains yes --run-filter no --directory "$ANALYSIS_DIR" --verbose "$SAS_VERBOSE_LEVEL"
else
  log "Skipping emchain/epchain (use --run-chains yes to enable)."
fi




# ------------------------------------------------------------------------
# Stage 1.6: Normalize filenames in analysis/
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.6: Normalize filenames in analysis/"
log "-------------------------------------------"

log "Normalizing event filenames…"

# Standardize filenames from raw EVL output to expected ESAS format
if ls *M1S001*EVL* >/dev/null 2>&1; then
  cp -f *M1S001*EVL* mos1S001.fits
else
  log "WARN: No MOS1 event list (*M1S001*EVL*) found"
fi

if ls *M2S002*EVL* >/dev/null 2>&1; then
  cp -f *M2S002*EVL* mos2S002.fits
else
  log "WARN: No MOS2 event list (*M2S002*EVL*) found"
fi

if ls *PN*IEVL* >/dev/null 2>&1; then
  cp -f *PN*IEVL* pnS003.fits
else
  log "WARN: No PN event list (*PN*IEVL*) found"
fi

if ls *PN*OEVL* >/dev/null 2>&1; then
  cp -f *PN*OEVL* pnS003-oot.fits
else
  log "Note: No PN OOT event list (*PN*OEVL*) found — continuing without it"
fi


# cp *M1U002*EVL* mos1S001.fits
# cp *M2U002*EVL* mos2S002.fits


# ------------------------------------------------------------------------
# Stage 1.7: Light curves & save rates/images
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.7: Light curves & save rates/images"
log "-------------------------------------------"

require dsplot

log "Generating light curves (ratem1/ratem2/ratepn) via: ${LIGHT_CURVES_SH##*/}"
bash "$LIGHT_CURVES_SH" --verbose "$SAS_VERBOSE_LEVEL"

# Verify rate tables exist
missing=0
for f in ratem1.fits ratem2.fits ratepn.fits; do
  if [[ ! -f "$f" ]]; then
    log "ERROR: expected $f but it wasn't created."
    missing=1
  fi
done
(( missing == 0 )) || die "step2_1.sh did not produce all rate files; check earlier logs."

# Launch dsplot windows (quietly) so user can inspect
log "Opening dsplot windows for rate inspection…"
( dsplot table=ratem1.fits x=TIME y=RATE.ERROR  >/dev/null 2>&1 & )
( dsplot table=ratem2.fits x=TIME y=RATE.ERROR  >/dev/null 2>&1 & )
( dsplot table=ratepn.fits x=TIME y=RATE.ERROR  >/dev/null 2>&1 & )

# Give xmgrace a moment to appear; then prompt
for _ in {1..10}; do
  if pgrep -x xmgrace >/dev/null 2>&1; then break; fi
  sleep 0.3
done
sleep 0.5

echo
read -rp "When you're done reviewing the three plots, press ENTER to continue… " _

# Prompt user to enter flare-rate thresholds
echo
echo "Enter flare-rate thresholds (cts/s). Press Enter for defaults."
read -rp "  MOS1 rate [0.20]: " M1R; M1R="${M1R:-0.20}"
read -rp "  MOS2 rate [0.20]: " M2R; M2R="${M2R:-0.20}"
read -rp "  PN   rate [0.30]: " PNR;  PNR="${PNR:-0.30}"

log "Flare-rate thresholds set: MOS1=${M1R}, MOS2=${M2R}, PN=${PNR}"





# ------------------------------------------------------------------------
# Stage 1.8: Save images and thresholds
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.8: Save images and thresholds"
log "-------------------------------------------"


# Helper function to save a dsplot PNG to qa/ directory
# Arguments: table_name output_basename [optional ymax]
save_plot() {
  local table="$1"
  local outbase="$2"
  local ymax="${3:-}"
  local ylim_args=""

  [[ -n "$ymax" ]] && ylim_args="withymin=yes ymin=0 withymax=yes ymax=$ymax"

  mkdir -p "$QA_DIR"
  if dsplot table="$table" x=TIME y=RATE.ERROR \
       $ylim_args \
       plotter="gracebat -hdevice PNG -printfile $QA_DIR/${outbase}.png -hardcopy -noask" \
       >/dev/null 2>&1; then
    log "Saved $QA_DIR/${outbase}.png"
    return 0
  else
    log "WARN: Failed to save $QA_DIR/${outbase}.png"
    return 1
  fi
}

# Save uncropped light curves
save_plot ratem1.fits rate_m1
save_plot ratem2.fits rate_m2
save_plot ratepn.fits rate_pn

# Save cropped versions (2× user-defined threshold)
save_plot ratem1.fits rate_m1_cropped "$(awk -v r="$M1R" 'BEGIN{printf "%.3f", 2*r}')"
save_plot ratem2.fits rate_m2_cropped "$(awk -v r="$M2R" 'BEGIN{printf "%.3f", 2*r}')"
save_plot ratepn.fits rate_pn_cropped "$(awk -v r="$PNR"  'BEGIN{printf "%.3f", 2*r}')"

# Save threshold values for use by future scripts
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/rates.env" <<EOF
# Saved by $(basename "$0") on $(date -u +"%F %T") UTC
export MOS1_RATE="${M1R}"
export MOS2_RATE="${M2R}"
export PN_RATE="${PNR}"
EOF

log "Saved thresholds to ${CONFIG_DIR#$BASE_DIR/}/rates.env : MOS1_RATE=${M1R}  MOS2_RATE=${M2R}  PN_RATE=${PNR}"
export MOS1_RATE="${M1R}"
export MOS2_RATE="${M2R}"
export PN_RATE="${PNR}"

# ------------------------------------------------------------------------
# Stage 1.9: Filter proton flare events with step2_2.sh
# Notes:
#   - To use a new rate run with --create-directories no --run-chains no
#   - Or, call step2_2.sh directly with the new rates
# ------------------------------------------------------------------------
log "-------------------------------------------"
log "Stage 1.9: Filter proton flare events"
log "-------------------------------------------"

log "Filtering proton flare events via: ${FILTER_FLARES_SH##*/}..."
bash "$FILTER_FLARES_SH" --verbose "$SAS_VERBOSE_LEVEL"


# File clean-up
mkdir -p "$OLD_FILES_DIR"

shopt -s nullglob  # So that 'mv' does nothing if no .FIT files exist
log "Moving old FIT files to: ${OLD_FILES_DIR#$BASE_DIR/}"
for file in "$ANALYSIS_DIR"/*.FIT; do
    mv "$file" "$OLD_FILES_DIR/"
done
shopt -u nullglob

log "Stage 1 complete. Next: Stage 2 - Cheese masks."
