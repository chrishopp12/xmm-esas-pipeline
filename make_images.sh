#!/usr/bin/env bash
###############################################################################
# Script Name : make_images.sh
# Description : Generates science images, exposure maps, and smoothed products.
#
# Usage:
#   ./make_images.sh [--m1-ccds "<mask>"] [--m2-ccds "<mask>"] 
#
# Arguments:
#   --m1-ccds "<mask>"   CCD include/exclude mask for MOS1 
#   --m2-ccds "<mask>"   CCD include/exclude mask for MOS2
###############################################################################


# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_images='[images]'
push_tag "$TAG_images"
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
usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --obs-id       <id>     Observation ID (e.g., 0881900301) [required]
  --base-dir     <path>   Base dir with /scripts and /blank_all
  --m1-ccds     "<mask>"  MOS1 CCD exclusion mask (e.g., "3,6" or "" for none)
  --m2-ccds     "<mask>"  MOS2 CCD exclusion mask 
  --pn-ccds     "<mask>"  PN CCD exclusion mask - Currently always TTTT
  --verbose               Verbosity: none|errors|all|0|1|2|yes|no     [default: "$VERBOSITY_DEFAULT"]
  -v | --verbose          Enable verbose SAS output
  -h | --help             Show help
EOF
}



# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"


while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --m1-ccds)            M1_CCDS_CLI="$2";                          shift 2;;
    --m2-ccds)            M2_CCDS_CLI="$2";                          shift 2;;
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
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"




# ------------------------------------------------------------------------
# Building and check directory
# ------------------------------------------------------------------------
  mkdir -p "$IMAGE_DIR"

  # Common file stems for all detectors
  COMMON_STEMS=(allevc bkgregtdet bkgregtsky corevc fovimt fovimtexp)

  # Loop over detectors and copy files (fail if missing)
  for det in mos1S001 mos2S002 pnS003; do
      for stem in "${COMMON_STEMS[@]}"; do
          src="${MASK_DIR}/${det}-${stem}.fits"
          [[ -f "$src" ]] || die "Missing required file: $src"
          cp "$src" "$IMAGE_DIR/"
      done
  done

  # PN-only extra file
  PN_EXTRA="${MASK_DIR}/pnS003-allevcoot.fits"
  [[ -f "$PN_EXTRA" ]] || die "Missing required file: $PN_EXTRA"
  cp "$PN_EXTRA" "$IMAGE_DIR/"

  # Cheese masks for all detectors
  for det in mos1S001 mos2S002 pnS003; do
      src="${MASK_DIR}/${det}-cheeset.fits"
      [[ -f "$src" ]] || die "Missing required file: $src"
      cp "$src" "$IMAGE_DIR/"
  done



  


# ------------------------------------------------------------------------
# Load CCD exclusion lists
# ------------------------------------------------------------------------

# -- CCD exclusion formatting --
make_ccd_mask() {
  local det="$1"
  local bad_list="$2"
  local mask=()

  # Warn + apply defaults
  if [[ -z "$bad_list" || "$bad_list" == "none" ]]; then
    if [[ "$det" == "m1" ]]; then
      log_warn "No CCD exclusion list for MOS1 — using default bad CCDs 3,6"
      bad_list="3,6"
    elif [[ "$det" == "m2" ]]; then
      log_warn "No CCD exclusion list for MOS2 — using default 'none'"
      bad_list=""
    fi
  fi

  # Convert to T/F eg. "3,6" -> 'T T F T T F T'
  for ccd in {1..7}; do
    if [[ -z "$bad_list" ]]; then
      mask+=("T")
    elif [[ "$bad_list" =~ (^|,)$ccd($|,) ]]; then
      mask+=("F")
    else
      mask+=("T")
    fi
  done

  echo "${mask[*]}"
}

# Get CCDS
EXCLUDE_CCDS_M1=$(get_ccds "${M1_CCDS_CLI:-}" EXCLUDE_CCDS_M1 "$CCDS_ENV_FILE" m1)
EXCLUDE_CCDS_M2=$(get_ccds "${M2_CCDS_CLI:-}" EXCLUDE_CCDS_M2 "$CCDS_ENV_FILE" m2)

# Build mask strings
M1_CCDS=$(make_ccd_mask "m1" "${EXCLUDE_CCDS_M1:-}")
M2_CCDS=$(make_ccd_mask "m2" "${EXCLUDE_CCDS_M2:-}")

log "M1 CCD mask string: [$M1_CCDS]"
log "M2 CCD mask string: [$M2_CCDS]"




# ------------------------------------------------------------------------
# Build images
# ------------------------------------------------------------------------
require mosspectra
require pnspectra
require mosback
require pnback
require rotdet2sky
require combimage
require binadapt

cd "$IMAGE_DIR"

log "Creating event spectra..."
run_verbose "mosspectra eventfile=mos1S001-allevc.fits withregion=no pattern=12 withsrcrem=yes maskdet=mos1S001-bkgregtdet.fits masksky=mos1S001-bkgregtsky.fits elow=400 ehigh=1100 ccds=\"${M1_CCDS}\""
run_verbose "mosspectra eventfile=mos2S002-allevc.fits withregion=no pattern=12 withsrcrem=yes maskdet=mos2S002-bkgregtdet.fits masksky=mos2S002-bkgregtsky.fits elow=400 ehigh=1100 ccds=\"${M2_CCDS}\""
run_verbose "pnspectra eventfile=pnS003-allevc.fits ootevtfile=pnS003-allevcoot.fits withregion=no pattern=0 withsrcrem=yes maskdet=pnS003-bkgregtdet.fits masksky=pnS003-bkgregtsky.fits elow=400 ehigh=1100 quads=\"T T T T\""

log "Creating model background spectra..."
run_verbose "mosback inspecfile=mos1S001-fovt.pi elow=400 ehigh=1100 ccds=\"${M1_CCDS}\""
run_verbose "mosback inspecfile=mos2S002-fovt.pi elow=400 ehigh=1100 ccds=\"${M2_CCDS}\""
run_verbose "pnback  inspecfile=pnS003-fovt.pi  inspecoot=pnS003-fovtoot.pi elow=400 ehigh=1100 quads=\"T T T T\""

run_verbose "rotdet2sky intemplate=mos1S001-fovimsky-400-1100.fits inimage=mos1S001-bkgimdet-400-1100.fits outimage=mos1S001-bkgimsky-400-1100.fits withdetxy=false withskyxy=false"
run_verbose "rotdet2sky intemplate=mos2S002-fovimsky-400-1100.fits inimage=mos2S002-bkgimdet-400-1100.fits outimage=mos2S002-bkgimsky-400-1100.fits withdetxy=false withskyxy=false"
run_verbose "rotdet2sky intemplate=pnS003-fovimsky-400-1100.fits inimage=pnS003-bkgimdet-400-1100.fits outimage=pnS003-bkgimsky-400-1100.fits withdetxy=false withskyxy=false"

log "Creating combined images..."
run_verbose "combimage prefixlist='1S001 2S002 S003' withpartbkg=true withspbkg=false withswcxbkg=false withcheese=true cheesetype=t elowlist=400 ehighlist=1100"

# -- Binned, not smoothed --
run_verbose "binadapt prefix=comb elow=400 ehigh=1100 withpartbkg=true withswcxbkg=false withspbkg=false withmask=false withbinning=true binfactor=4 withsmoothing=false"
cp comb-rateimsky-400-1100.fits comb-bin.fits

# -- Smoothed, not binned --
run_verbose "binadapt prefix=comb elow=400 ehigh=1100 withpartbkg=true withswcxbkg=false withspbkg=false withmask=false withbinning=false withsmoothing=true smoothcounts=50"
cp comb-adaptimsky-400-1100.fits comb-smooth.fits

# -- Binned and smoothed --
run_verbose "binadapt prefix=comb elow=400 ehigh=1100 withpartbkg=true withswcxbkg=false withspbkg=false withmask=false withbinning=true binfactor=4 withsmoothing=true smoothcounts=50"

pop_tag "$TAG_images"