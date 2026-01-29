###############################################################################
# Script Name : make_regions.sh
# Description : Creates DS9 region files for source and background regions in detector coordinates.
#
# Usage:
#   source resolve_paths.sh --obs-id <id> --base-dir <path> [--verbose <level>]
#
# Example:
#   source ./scripts/resolve_paths.sh --obs-id "0881900301" --base-dir "/Users/you/Desktop/XMM"
#
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
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_regions='[make_regions]'
push_tag "$TAG_regions"
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
  source $(basename "$0") --obs-id <id> --base-dir <path> [--verbose <level>]

Options:
  --obs-id <id>        Observation ID (e.g., 0881900301) [required]
  --base-dir <path>    Base directory with /scripts and /observation_data [required]
  --verbose <level>    Verbosity: none|errors|all|0|1|2|yes|no [default: ${VERBOSITY_DEFAULT}]
  -v | --verbose       Enable verbose SAS output
  -h | --help          Show help
EOF
}


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
    -h|--help)            usage;                                 exit 0;;
    *)                    echo "Unknown arg: $1"; usage;    exit 1;;
  esac
done


# Use defaults if not provided
OBS_ID="${OBS_ID:-$OBS_ID_DEFAULT}"
BASE_DIR="${BASE_DIR:-$BASE_DIR_DEFAULT}"


# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"

# Sanity check required files and scripts
[[ -d "$ANALYSIS_DIR" ]] || die "Analysis dir not found: $ANALYSIS_DIR"
[[ -d "$SCRIPTS_DIR"  ]] || die "Scripts dir not found: $SCRIPTS_DIR"
[[ -d "$CONFIG_DIR"   ]] || die "Config dir not found: $CONFIG_DIR"


# ------------------------------------------------------------------------
# Create region files
# ------------------------------------------------------------------------

REGION_SCRIPT="${SCRIPTS_DIR}/region_ds9.py"
mkdir -p "$CONFIG_DIR"

python3 "${REGION_SCRIPT}" \
  --analysis-root "${ANALYSIS_DIR}" \
  --script-path "${SCRIPTS_DIR}" \
  --obs-id "${OBS_ID}" \
  --region both \
   >/tmp/regions.out


# Parse the printed "src: circle(...)" / "bkg: circle(...)" lines in order m1,m2,pn
M1_SRC=$(awk '/^src:/{print $2}' /tmp/regions.out | sed -n '1p')
M2_SRC=$(awk '/^src:/{print $2}' /tmp/regions.out | sed -n '2p')
PN_SRC=$(awk '/^src:/{print $2}' /tmp/regions.out | sed -n '3p')
M1_BKG=$(awk '/^bkg:/{print $2}' /tmp/regions.out | sed -n '1p')
M2_BKG=$(awk '/^bkg:/{print $2}' /tmp/regions.out | sed -n '2p')
PN_BKG=$(awk '/^bkg:/{print $2}' /tmp/regions.out | sed -n '3p')

cat > "${CONFIG_DIR}/regions.env.tmp" <<EOF
M1_REG='${M1_SRC}'
M1_REG2='${M1_BKG}'
M2_REG='${M2_SRC}'
M2_REG2='${M2_BKG}'
PN_REG='${PN_SRC}'
PN_REG2='${PN_BKG}'
EOF

mv "${CONFIG_DIR}/regions.env.tmp" "${CONFIG_DIR}/regions.env"

# Log region_ds9.py output
TAG_regions_py='[regions_py]'
push_tag "$TAG_regions_py"
while IFS= read -r line; do
    log_info "$line"
done < /tmp/regions.out
pop_tag "$TAG_regions_py"

rm -f /tmp/regions.out

log "Wrote ${CONFIG_DIR#$BASE_DIR/}/regions.env"

pop_tag "$TAG_regions"

