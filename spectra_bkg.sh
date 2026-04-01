#!/usr/bin/env bash
###############################################################################
# Script Name : spectra_bkg.sh
# Description : Prepares secondary background spectra for m1.
#
# Usage:
#   ./spectra_bkg.sh --obs-id <id> --base-dir <path> --det <detector> [options]
#
# Arguments:
#   --obs-id      <id>        Observation ID (e.g., 0881900301) [required]
#   --base-dir    <path>      Base dir with /scripts and /observation_data
#   --det         <detector>  Detector to process (e.g., m1)
#   --bkg-reg    "<string>"   Background region (DETX/DETY), must include circle() or annulus() syntax
#   --verbose                  Verbosity: none|errors|all|0|1|2|yes|no             [default: errors]
#   -v | --verbose             Enable verbose SAS output
#   -h | --help                Show help
###############################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"


# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_spec_bkg='[spectra_bkg]'
push_tag "$TAG_spec_bkg"
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
BKG_REG_COORD_DEFAULT=""
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
  --det             <detector>  Detector to process (e.g., m1)
  --bkg-reg        "<string>"   Background region (e.g., circle(300,400,100))
  --verbose         <level>     Verbosity: none|errors|all|0|1|2|yes|no     [default: ${VERBOSITY_DEFAULT}]
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
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --det)                DET="$2";                              shift 2;;
    --bkg-reg)            BKG_REG_COORD="$2";                    shift 2;;
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
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"
DET="${DET:-$DET_DEFAULT}"
BKG_REG_COORD="${BKG_REG_COORD:-$BKG_REG_COORD_DEFAULT}"

# Sanity checks
[[ -n "$OBS_ID" ]] || { usage; exit 1; }
[[ -d "$BASE_DIR" ]] || die "Base dir not found: $BASE_DIR"

# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"


# -- Detector file identifiers --

# Try to infer detector if not specified
if [[ -z "$DET" ]]; then
  case "$(basename "$PWD")" in
    m1|m2|pn) DET="$(basename "$PWD")";;
    *)        die "Must specify --det (m1, m2, or pn)";;
  esac
fi

case "$DET" in
  m1) REGION=$M1_REG2; FOLDER="${M1_DIR:-.}"; EXP="#XMMEA_EM && (PATTERN<=12)"; SPEC_CHANNEL=11999;;
  m2) REGION=$M2_REG2; FOLDER="${M2_DIR:-.}"; EXP="#XMMEA_EM && (PATTERN<=12)"; SPEC_CHANNEL=11999;;
  pn) REGION=$PN_REG2; FOLDER="${PN_DIR:-.}"; EXP="#XMMEA_EP && (PATTERN<=4) && (FLAG==0)"; SPEC_CHANNEL=20479;;
  *)  die "Invalid --det: $DET (use m1|m2|pn)";;
esac


# -- Get regions --
load_regions

if [[ -z "$BKG_REG_COORD" ]]; then
  BKG_REG_COORD="${REGION:-}"
fi

[[ -n "$BKG_REG_COORD" ]] || die "Could not determine background region ($REGION or --bkg-reg)!"
export BKG_REG_COORD




# ------------------------------------------------------------------------
# Run SAS tasks
# ------------------------------------------------------------------------
require evselect

# Observation
log "Creating observation background spectrum"
run_verbose "evselect table='${FOLDER}/${DET}clean_mask.fits' withzcolumn=Y withzerrorcolumn=N withspectrumset=yes spectrumset='${FOLDER}/${DET}source2_spectrum.fits' energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=${SPEC_CHANNEL}  imagebinning=binSize imageset='${FOLDER}/${DET}source2_spectrum_image.fits' withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression='${EXP} && ((DETX,DETY) IN $BKG_REG_COORD)'"

run_verbose "backscale spectrumset='${FOLDER}/${DET}source2_spectrum.fits' badpixlocation='${FOLDER}/${DET}clean_mask.fits'"
# Background region RMF/ARF not used by double subtraction (mathpha operates in count space).
# Uncomment if needed for diagnostic fits of the background region spectrum.
# run_verbose "rmfgen spectrumset='${FOLDER}/${DET}source2_spectrum.fits' rmfset='${FOLDER}/${DET}source2.rmf' detmaptype=flat"
# run_verbose "arfgen spectrumset='${FOLDER}/${DET}source2_spectrum.fits' arfset='${FOLDER}/${DET}source2.arf' withrmfset=yes rmfset='${FOLDER}/${DET}source2.rmf' badpixlocation='${FOLDER}/${DET}clean_mask.fits' extendedsource=yes withbadpixcorr=Y modelee=N withdetbounds=Y filterdss=N detmaptype=flat detxbins=1 detybins=1 withsourcepos=Y sourcecoords=tel sourcex=0 sourcey=0 applyxcaladjustment=yes"

# Blank sky
log "Creating blank sky background spectrum"
run_verbose "evselect table='${FOLDER}/${DET}bkg_clean_mask.fits' withzcolumn=Y withzerrorcolumn=N withspectrumset=yes spectrumset='${FOLDER}/${DET}bkg2_spectrum.fits' energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=${SPEC_CHANNEL}  imagebinning=binSize imageset='${FOLDER}/${DET}bkg2_spectrum_image.fits' withimageset=yes xcolumn=DETX ycolumn=DETY ximagebinsize=80 yimagebinsize=80 expression='${EXP} && ((DETX,DETY) IN $BKG_REG_COORD)'"

run_verbose "backscale spectrumset='${FOLDER}/${DET}bkg2_spectrum.fits' badpixlocation='${FOLDER}/${DET}bkg_clean_mask.fits'"


pop_tag "$TAG_spec_bkg"