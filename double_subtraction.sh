#!/usr/bin/env bash
############################################################################################################
# Script Name : double_subtraction.sh
# Description : Performs double-subtraction background correction for spectra.
#
# Usage:
#   ./double_subtraction.sh [options]
#
# Arguments:
#   --obs-id             <id>      Observation ID [required]
#   --base-dir           <path>    Base dir with /scripts and /observation_data 
#   --detectors          <list>    Comma-separated detectors to run            [default: "m1,m2,pn"]
#   --bad-channels-mos  "<range>"  XSPEC MOS bad channels                      [default:"0-60 2000-2399"]
#   --bad-channels-pn   "<range>"  XSPEC PN bad channels                       [default:"0-80 2001-4095"]
#   --group-min          <int>     Minimum counts per bin                      [default: 20]
#   --verbose                      Verbosity: none|errors|all|0|1|2|yes|no     [default: errors]
#   -v | --verbose                 Enable verbose SAS output
#   -h | --help                    Show help
############################################################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"
TAG_double_subtract='[double_subtraction]'
push_tag "$TAG_double_subtract"
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
DETS_DEFAULT='m1,m2,pn'
MOS_BAD_DEFAULT='0-60 2000-2399'
PN_BAD_DEFAULT='0-80 2001-4095'
GROUP_MIN_DEFAULT=20




# ------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------
usage() {
  cat << EOF
Usage:
  $(basename "$0") [options]

Options:
  --obs-id             <id>       Observation ID (e.g., 0881900301) [required]
  --base-dir           <path>     Base dir with /scripts and /blank_all
  --detectors          <list>     Comma-separated detectors to run          [default: "$DETS_DEFAULT"]
  --bad-channels-mos  "<range>"   XSPEC MOS bad channels                    [default:"$MOS_BAD_DEFAULT"]
  --bad-channels-pn   "<range>"   XSPEC PN bad channels                     [default:"$PN_BAD_DEFAULT"]
  --group-min          <int>      Minimum counts per bin                    [default: $GROUP_MIN_DEFAULT]
  --verbose                       Verbosity: none|errors|all|0|1|2|yes|no   [default: "$VERBOSITY_DEFAULT"]
  -v | --verbose                  Enable verbose SAS output
  -h | --help                     Show help
EOF
}




# ------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------
# -- Check for env vars --
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"

MOS_BAD=${MOS_BAD:-$MOS_BAD_DEFAULT}
PN_BAD=${PN_BAD:-$PN_BAD_DEFAULT}
GROUP_MIN=${GROUP_MIN:-$GROUP_MIN_DEFAULT}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)            OBS_ID="$2";                           shift 2;;
    --base-dir)          BASE_DIR="$2";                         shift 2;;
    --detectors)         DETS="$2";                             shift 2;;
    --bad-channels-mos)  MOS_BAD="$2";                          shift 2;;
    --bad-channels-pn)   PN_BAD="$2";                           shift 2;;
    --group-min)         GROUP_MIN="$2";                        shift 2;;
    --verbose)           if [[ -n "${2-}" && $2 != -* ]]; then
                         verbose_level "$2";                    shift 2; else
                         verbose_level all;                     shift  ; fi ;;
    -v)                  verbose_level all;                     shift ;;
    -h|--help)           usage;                                 exit 0;;
    *)                   echo "Unknown arg: $1"; usage;    exit 1;;
  esac
done


DETS=${DETS:-$DETS_DEFAULT}
IFS=',' read -ra DET_ARR <<< "$DETS"

# Sanity checks
[[ -n "$OBS_ID" ]] || { usage; exit 1; }
[[ -d "$BASE_DIR" ]] || die "Base dir not found: $BASE_DIR"




# ------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------
log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  DETS          = ${DETS}"
log "  MOS_BAD       = ${MOS_BAD}"
log "  PN_BAD        = ${PN_BAD}"
log "  GROUP_MIN     = ${GROUP_MIN}"
log ""



# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"


# Sanity check required files and scripts
[[ -d "$ANALYSIS_DIR" ]]     || die "Analysis dir not found: $ANALYSIS_DIR"
[[ -d "$M1_DIR" ]]           || die "M1 dir not found: $M1_DIR"
[[ -d "$M2_DIR" ]]           || die "M2 dir not found: $M2_DIR"
[[ -d "$PN_DIR" ]]           || die "PN dir not found: $PN_DIR"

# ------------------------------------------------------------------------
# Perform double subtraction
# ------------------------------------------------------------------------

process_detector() {
  local DET=$1
  local A1 A2 A3 A4 Q rate1 rate2 tmp_xspec tmp_grppha

  tmp_xspec=$(mktemp)
  tmp_grppha=$(mktemp)
  set -e


# -- XSpec BACKSCAL --
  A1=$(fitsheader "${ANALYSIS_DIR}/${DET}/${DET}source_spectrum.fits" --e 1 | awk -F'= ' '/BACKSCAL/{print $2}' | awk '{print $1}')
  A2=$(fitsheader "${ANALYSIS_DIR}/${DET}/${DET}bkg_spectrum.fits"    --e 1 | awk -F'= ' '/BACKSCAL/{print $2}' | awk '{print $1}')
  A3=$(fitsheader "${ANALYSIS_DIR}/${DET}/${DET}source2_spectrum.fits" --e 1 | awk -F'= ' '/BACKSCAL/{print $2}' | awk '{print $1}')
  A4=$(fitsheader "${ANALYSIS_DIR}/${DET}/${DET}bkg2_spectrum.fits"    --e 1 | awk -F'= ' '/BACKSCAL/{print $2}' | awk '{print $1}')

# -- XSpec Rates --
  xspec - <<EOF > "$tmp_xspec" 2>&1
data 1:1 ${ANALYSIS_DIR}/${DET}/${DET}_proton_spectrum.fits
data 2:2 ${ANALYSIS_DIR}/${DET}/${DET}bkg_proton_spectrum.fits
query yes
tclout rate 1
puts "RATE1: \$xspec_tclout"
tclout rate 2
puts "RATE2: \$xspec_tclout"
exit
EOF

  rate1=$(awk '/^RATE1:/{print $2}' "$tmp_xspec")
  rate2=$(awk '/^RATE2:/{print $2}' "$tmp_xspec")
  [[ -z "$rate1" || -z "$rate2" ]] && { log "Failed to parse rates for $DET" >&2; exit 1; }

# -- Q Calculation --
  Q=$(awk -v r1="$rate1" -v r2="$rate2" 'BEGIN{ if(r2==0){print "NaN"} else {printf "%.6f", r1/r2} }')

  log ""
  log "==== Results summary for $DET ===="
  log "  A1 = $A1 (source_spectrum)"
  log "  A2 = $A2 (background_spectrum)"
  log "  A3 = $A3 (source2_spectrum)"
  log "  A4 = $A4 (background2_spectrum)"
  log "  Rate 1 = $rate1 (proton_spectrum)"
  log "  Rate 2 = $rate2 (bkg_proton_spectrum)"
  log "  Q = $Q (Rate1/Rate2)"
  log "==============================="
  log ""

  # If verbose=yes, append full XSPEC session to log
  if [ "${SAS_VERBOSE_LEVEL:-0}" -ge 2 ]; then
    [[ -n "${LOG_FILE:-}" ]] && cat "$tmp_xspec" >> "$LOG_FILE"
  fi
  rm -f "$tmp_xspec"


# -- Double subtraction calcs --
  case "$DET" in
      m1) cd "$M1_DIR" ;;
      m2) cd "$M2_DIR" ;;
      pn) cd "$PN_DIR" ;;
  esac

  run_verbose "mathpha expr=\"${DET}source_spectrum.fits-($A1/$A2)*($Q*${DET}bkg_spectrum.fits)\" \
          units='R' outfil=\"!${DET}_combined.fits\" properr=yes ERRMETH='Gauss' \
          areascal=\"${DET}source_spectrum.fits\" exposure=\"${DET}source_spectrum.fits\" ncomments=0"

  run_verbose "mathpha expr=\"($A1/$A3)*${DET}source2_spectrum.fits-($A1/$A4)*($Q*${DET}bkg2_spectrum.fits)\" \
          units='R' outfil=\"!${DET}_combined2.fits\" properr=yes ERRMETH='Gauss' \
          areascal=\"${DET}source2_spectrum.fits\" exposure=\"${DET}source2_spectrum.fits\" ncomments=0"

  run_verbose "mathpha expr=\"${DET}_combined.fits-${DET}_combined2.fits\" \
          units='R' outfil=\"!${DET}_final.fits\" properr=yes ERRMETH='Gauss' \
          areascal=\"${DET}_combined.fits\" exposure=\"${DET}_combined.fits\" ncomments=0"



# -- Grouping --

if [ "$DET" = "pn" ]; then
  BAD=$PN_BAD
  MAXCH=4095
else
  BAD=$MOS_BAD
  MAXCH=2399
fi

grppha ${DET}_final.fits ${DET}_final_grp.fits << EOF | tee "$tmp_grppha"
good 0-$MAXCH
chkey RESPFILE ${DET}source.rmf
chkey ANCRFILE ${DET}source.arf
bad $BAD
group min $GROUP_MIN
show all
write !${DET}_final_grp.fits
exit
EOF

# find GOOD single-channel groups and bad them
ftlist ${DET}_final_grp.fits+1 data column=CHANNEL,GROUPING,QUALITY | \
awk '/^[[:space:]]*[0-9]/{ch=$1; gp=$2; q=$3; if(q>0) {start=-1; next}
     if(start<0) start=ch; if(gp==1){ if(ch==start) printf "%d %d\n",ch,ch; start=-1 }}' \
> /tmp/${OBS_ID}_${DET}_singles.txt

if [ -s /tmp/${OBS_ID}_${DET}_singles.txt ]; then
  grppha ${DET}_final_grp.fits ${DET}_final_grp.fits << EOF | tee -a "$tmp_grppha"
bad @/tmp/${OBS_ID}_${DET}_singles.txt
show quality
write !${DET}_final_grp.fits
exit
EOF
fi

# how many channels are now BAD?
ftselect infile=${DET}_final_grp.fits+1 outfile=/tmp/${OBS_ID}_${DET}_bad.fits expression="QUALITY>0" clobber=yes
ftlist /tmp/${OBS_ID}_${DET}_bad.fits+1 K | awk -F= '/NAXIS2/{print "QUALITY>0 rows:", $2}'




#   if [ "$DET" = "pn" ]; then
#     BAD=$PN_BAD
#   else
#     BAD=$MOS_BAD
#   fi

#   grppha ${DET}_final.fits ${DET}_final_grp.fits << EOF | tee "$tmp_grppha"
# good 0 4095
# chkey RESPFILE ${DET}source.rmf
# chkey ANCRFILE ${DET}source.arf
# bad $BAD
# group min $GROUP_MIN
# show all
# write !${DET}_final_grp.fits
# exit
# EOF

# # Build a list of single-channel groups
# ftlist ${DET}_final_grp.fits+1 data column=CHANNEL,GROUPING \
# | awk '
#   BEGIN{start=-1}
#   /^[[:space:]]*[0-9]/{ch=$1; gp=$2;
#     if (start<0) start=ch;
#     if (gp==1) { if (ch==start) print ch; start=-1; } else { if (start<0) start=ch; }
#   }' > /tmp/${DET}_singles.txt

# # If any were found, mark them bad in-place
# if [ -s /tmp/${DET}_singles.txt ]; then
#   grppha ${DET}_final_grp.fits ${DET}_final_grp.fits << EOF > /dev/null
# bad @/tmp/${DET}_singles.txt
# write !${DET}_final_grp.fits
# exit
# EOF
# fi
# rm -f /tmp/${DET}_singles.txt


#   grppha ${DET}_final.fits ${DET}_final_grp.fits << EOF > "$tmp_grppha" 2>&1
# chkey RESPFILE ${DET}source.rmf
# chkey ANCRFILE ${DET}source.arf
# bad $BAD
# group min $GROUP_MIN
# show ALL
# write !${DET}_final_grp.fits
# exit
# EOF


# --- Grouping audit (after grppha) ---
tot_ch=$(
  ftlist "${DET}_final_grp.fits+1" K | awk -F= '/NAXIS2/{gsub(/[[:space:]]/,"",$2); print $2}'
)

# how many grouped bins? (count GROUPING==1)
ftselect infile="${DET}_final_grp.fits+1" outfile="/tmp/${OBS_ID}_${DET}_grpends.fits" \
         expression="GROUPING==1" clobber=yes >/dev/null 2>&1
n_bins=$(
  ftlist "/tmp/${OBS_ID}_${DET}_grpends.fits+1" K 2>/dev/null \
  | awk -F= '/NAXIS2/{gsub(/[[:space:]]/,"",$2); print $2}'
)

# how many channels flagged bad?
ftselect infile="${DET}_final_grp.fits+1" outfile="/tmp/${OBS_ID}_${DET}_bad.fits" \
         expression="QUALITY>0" clobber=yes >/dev/null 2>&1
n_bad=$(
  ftlist "/tmp/${OBS_ID}_${DET}_bad.fits+1" K 2>/dev/null \
  | awk -F= '/NAXIS2/{gsub(/[[:space:]]/,"",$2); print $2}'
)

# peek at the first few rows (optional)
ftlist "${DET}_final_grp.fits+1" data column="CHANNEL,GROUPING,QUALITY" rows=1-40 | head -n 40 \
  > "/tmp/${OBS_ID}_${DET}_group_preview.txt"

echo "[${DET}] channels=${tot_ch}  bins=${n_bins}  bad_rows=${n_bad}" | tee -a "$LOG_FILE"
[[ -n "${LOG_FILE:-}" ]] && {
  echo "[${DET}] First rows CHANNEL,GROUPING,QUALITY →" >> "$LOG_FILE"
  cat "/tmp/${OBS_ID}_${DET}_group_preview.txt" >> "$LOG_FILE"
}

rm -f "/tmp/${OBS_ID}_${DET}_grpends.fits" "/tmp/${OBS_ID}_${DET}_bad.fits" "/tmp/${OBS_ID}_${DET}_group_preview.txt"
# --- end audit ---


  log "Grouped spectrum written to: /${DET}/${DET}_final_grp.fits"
  if [ "${SAS_VERBOSE_LEVEL:-0}" -ge 1 ]; then
    [[ -n "${LOG_FILE:-}" ]] && cat "$tmp_grppha" >> "$LOG_FILE"
  fi
  rm -f "$tmp_grppha"

  cd - > /dev/null
}



# ------------------------
# Process each detector
# ------------------------
for d in "${DET_ARR[@]}"; do
  process_detector "$d"
done



# ------------------------
# Copy final products to subtracted directory
# ------------------------
mkdir -p subtracted
cp "$M1_DIR"/m1_final_grp.fits "$M1_DIR"/m1source.rmf "$M1_DIR"/m1source.arf subtracted/ 2>/dev/null || true
cp "$M2_DIR"/m2_final_grp.fits "$M2_DIR"/m2source.rmf "$M2_DIR"/m2source.arf subtracted/ 2>/dev/null || true
cp "$PN_DIR"/pn_final_grp.fits "$PN_DIR"/pnsource.rmf "$PN_DIR"/pnsource.arf subtracted/ 2>/dev/null || true

pop_tag "$TAG_double_subtract"