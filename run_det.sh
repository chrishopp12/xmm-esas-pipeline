#!/usr/bin/env bash
####################################################################################################
# Script Name : run_det.sh
# Description : Full reduction sequence for m1 from filtered events to spectra.
#
# Usage:
#   ./run_det.sh [OPTIONS]
#
# Arguments:
#   --exclude-ccds "<mask>"  CCD/quad exclusion mask (default: "3,6" to exclude CCDs 3 and 6)
#   --bkg-rate <float>       Background flare threshold
#   --vig-mode "<string>"    Vignetting mode: both|blank|obs|none (default: both)
#   --date-obs "<string>"    Observation start date/time (ISO format)
#   --date-end "<string>"    Observation end date/time (ISO format)
#   --reg-src "<string>"     Source region (DETX/DETY), must include circle() or annulus() syntax
#   --reg-bkg "<string>"     Background region (DETX/DETY), must include circle() or annulus() syntax
#   --verbose           [<yes|true|no|false>]   Enable verbose output             [default: no]
####################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_run_det='[run_det]'
push_tag "$TAG_run_det"
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
EXCLUDE_CCDS_DEFAULT=""
BKG_RATE_DEFAULT=""
VIG_MODE_DEFAULT="both"
DATE_OBS_DEFAULT=""
DATE_END_DEFAULT=""
REG_SRC_DEFAULT=""
REG_BKG_DEFAULT=""
DET_DEFAULT=""



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
  --det            <detector>   Detector to process (e.g., m1)
  --exclude-ccds  "<mask>"      CCD/quad exclusion mask
  --bkg-rate       <float>      Background flare threshold
  --vig-mode       "<string>"   Vignetting mode: both|blank|obs|none                 [default: both]
  --date-obs       "<string>"   Start date/time in ISO format
  --date-end       "<string>"   End date/time in ISO format
  --reg-src        "<string>"   Source region (DETX/DETY), must include circle()
  --reg-bkg        "<string>"   Background region (DETX/DETY), must include circle()
  --verbose         <level>     Verbosity: none|errors|all|0|1|2|yes|no               [default: ${VERBOSITY_DEFAULT}]
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
EXCLUDE_CCDS="$EXCLUDE_CCDS_DEFAULT"
BKG_RATE="$BKG_RATE_DEFAULT"
VIG_MODE="$VIG_MODE_DEFAULT"
DATE_OBS="$DATE_OBS_DEFAULT"
DATE_END="$DATE_END_DEFAULT"
REG_SRC="$REG_SRC_DEFAULT"
REG_BKG="$REG_BKG_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)       OBS_ID="$2";                           shift 2;;
    --base-dir)     BASE_DIR="$2";                         shift 2;;
    --det)          DET="$2";                              shift 2;;
    --exclude-ccds) EXCLUDE_CCDS="$2";                     shift 2;;
    --bkg-rate)     BKG_RATE="$2";                         shift 2;;
    --vig-mode)     VIG_MODE="$2";                         shift 2;;
    --date-obs)     DATE_OBS="$2";                         shift 2;;
    --date-end)     DATE_END="$2";                         shift 2;;
    --reg-src)      REG_SRC="$2";                          shift 2;;
    --reg-bkg)      REG_BKG="$2";                          shift 2;;
    --verbose)      if [[ -n "${2-}" && $2 != -* ]]; then
                    verbose_level "$2";                    shift 2; else
                    verbose_level all;                     shift  ; fi ;;
    -v)             verbose_level all;                     shift ;;
    -h|--help)      usage;                                 exit 0;;
    *)              echo "Unknown arg: $1"; usage;         exit 1;;
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
# Prep detector variables
# ------------------------------------------------------------------------

# Try to infer detector if not specified
if [[ -z "$DET" ]]; then
  case "$(basename "$PWD")" in
    m1|m2|pn) DET="$(basename "$PWD")";;
    *)        die "Must specify --det (m1, m2, or pn)";;
  esac
fi


log "Preparing detector variables for $DET..."
# -- Detector file identifiers --
case "$DET" in
  m1) SPEC_CHANNEL=11999;;
  m2) SPEC_CHANNEL=11999;;
  pn) SPEC_CHANNEL=20479;;
  *)  die "Invalid --det: $DET (use m1|m2|pn)";;
esac

CCD_ENV="EXCLUDE_CCDS_$(echo "$DET" | tr '[:lower:]' '[:upper:]')"
FOLDER="$(dir_of "$DET")"
NAME="$(name_of "$DET")"

# -- Get CCD exclusion mask --
if [[ -z "${EXCLUDE_CCDS:-}" ]]; then
  EXCLUDE_CCDS="$(get_ccds "${EXCLUDE_CCDS}" "${CCD_ENV}" "${CCDS_ENV_FILE}" "$DET")"
fi
log "Using CCD exclusion mask: $EXCLUDE_CCDS"

log "Creating exclusion expression..."
if [[ -z "$EXCLUDE_CCDS" || "$EXCLUDE_CCDS" == "none" ]]; then
  EXCL_EXPR=""
else
  EXCL_EXPR=""
  IFS=',' read -ra _ccds <<< "$EXCLUDE_CCDS"
  for c in "${_ccds[@]}"; do
    c_trimmed=$(echo "$c" | xargs)
    [[ -n "$c_trimmed" ]] && EXCL_EXPR+=" && (CCDNR!=$c_trimmed)"
  done
fi
log "Exclusion expression for $DET: $EXCL_EXPR"



# ------------------------------------------------------------------------
# Prep blank sky files
# ------------------------------------------------------------------------
# -- Get blank sky files --
ensure_blank_for_evt "$DET"


# -- Write blank sky dates --
if [[ -n "$DATE_OBS" && -n "$DATE_END" ]]; then
  bash ${SCRIPTS_DIR}/fparkey_bkg.sh --det "$DET" --date-obs "$DATE_OBS" --date-end "$DATE_END" --verbose "$SAS_VERBOSE_LEVEL"
else
  bash ${SCRIPTS_DIR}/fparkey_bkg.sh --det "$DET" --verbose "$SAS_VERBOSE_LEVEL"
fi


# -- Apply vignetting correction --
case "$VIG_MODE" in
  both)  
         log "Applying vignetting correction to blank sky file..."
         run_verbose "evigweight ineventset='$(blank_of "$DET")'"
         log "Applying vignetting correction to observation file..."
         run_verbose "evigweight ineventset='$(allevc_of "$DET")'" ;;
  blank) 
         log "Applying vignetting correction to blank sky file..."
         run_verbose "evigweight ineventset='$(blank_of "$DET")'" ;;
  obs)   
         log "Applying vignetting correction to observation file..."
         run_verbose "evigweight ineventset='$(allevc_of "$DET")'" ;;
  none)  : ;;  # do nothing
  *) die "Invalid --vig mode: $VIG_MODE (use both|blank|obs|none)";;
esac

# Background flare filtering
bash ${SCRIPTS_DIR}/proton_blank.sh ${BKG_RATE:+--rate "$BKG_RATE"} --det "$DET" --verbose "$SAS_VERBOSE_LEVEL"

# Apply mask region

run_verbose "evselect table='$(allevc_of "$DET")' withfilteredset=Y filteredset='${FOLDER}/${DET}clean_mask.fits' destruct=Y keepfilteroutput=T imagebinning=binSize imageset='${FOLDER}/${DET}image_mask.fits' withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression='region(${FOLDER}/${NAME}-bkgregtdet.fits,DETX,DETY)${EXCL_EXPR}'"

run_verbose "evselect table='${FOLDER}/${DET}bkg_clean.fits' withfilteredset=Y filteredset='${FOLDER}/${DET}bkg_clean_mask.fits' destruct=Y keepfilteroutput=T imagebinning=binSize imageset='${FOLDER}/${DET}bkg_image_mask.fits' withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression='region(${FOLDER}/${NAME}-bkgregtdet.fits,DETX,DETY)${EXCL_EXPR}'"

bash ${SCRIPTS_DIR}/spectra_src.sh ${REG_SRC:+--src-reg "$REG_SRC"} --det "$DET" --verbose "$SAS_VERBOSE_LEVEL"
bash ${SCRIPTS_DIR}/spectra_bkg.sh ${REG_BKG:+--bkg-reg "$REG_BKG"} --det "$DET" --verbose "$SAS_VERBOSE_LEVEL"




run_verbose "evselect table='${FOLDER}/${DET}clean_mask.fits' withzcolumn=Y withzerrorcolumn=N withfilteredset=Y filteredset='${FOLDER}/${DET}_proton.fits' destruct=Y keepfilteroutput=T imagebinning=binSize imageset='${FOLDER}/${DET}_proton_image.fits' withimageset=yes withspectrumset=yes spectrumset='${FOLDER}/${DET}_proton_spectrum.fits' energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=${SPEC_CHANNEL}  xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression='(PATTERN==0) && (FLAG==0)$EXCL_EXPR && (PI>10000&&PI<12000)'"

run_verbose "evselect table='${FOLDER}/${DET}bkg_clean_mask.fits' withzcolumn=Y withzerrorcolumn=N withfilteredset=Y filteredset='${FOLDER}/${DET}bkg_proton.fits' destruct=Y keepfilteroutput=T imagebinning=binSize imageset='${FOLDER}/${DET}bkg_proton_image.fits' withimageset=yes withspectrumset=yes spectrumset='${FOLDER}/${DET}bkg_proton_spectrum.fits' energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=${SPEC_CHANNEL}  xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression='(PATTERN==0) && (FLAG==0)$EXCL_EXPR && (PI>10000&&PI<12000)'"

# Headers preview
for f in "${FOLDER}/${DET}source_spectrum.fits" "${FOLDER}/${DET}bkg_spectrum.fits" "${FOLDER}/${DET}source2_spectrum.fits" "${FOLDER}/${DET}bkg2_spectrum.fits"; do
  fitsheader "$f" --e 1 | grep BACKSCAL || true
done

pop_tag "$TAG_run_det"