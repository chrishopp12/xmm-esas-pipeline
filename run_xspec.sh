#!/usr/bin/env bash
###############################################################################
# Script Name : run_xspec.sh
# Description : Launches XSPEC with preconfigured model for reduced spectra.
#
# Usage:
#   ./run_xspec.sh [--z <redshift>] [--nh <nH>]
#
# Arguments:
#   --obs-id     <id>       Observation ID (required)
#   --base-dir   <path>     Base dir with /scripts and /observation_data
#   --z          <float>    Cluster redshift
#   --nh         <float>    Galactic hydrogen column density (in 1e22 cm^-2)
#   --verbose               Verbosity: none|errors|all|0|1|2|yes|no     [default: errors]
#   -v | --verbose          Enable verbose SAS output
#   -h | --help             Show help
###############################################################################

# ------------------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------------------
set -euo pipefail
ORIGINAL_CALL="$*"

# -- Load helpers -- 
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPTS_DIR:-$SCRIPT_DIR}/helpers.sh"

TAG_xspec='[run_xspec]'
push_tag "$TAG_xspec"
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
  cat << EOF
Usage:
  $(basename "$0") [options]

Options:
  --obs-id             <id>       Observation ID (e.g., 0881900301) [required]
  --base-dir           <path>     Base dir with /scripts and /blank_all
  --z                  <float>    Cluster redshift
  --nh                 <float>    Galactic hydrogen column density (in 1e22 cm^-2)
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --obs-id)             OBS_ID="$2";                           shift 2;;
    --base-dir)           BASE_DIR="$2";                         shift 2;;
    --z)                  Z_CLI="$2";                            shift 2;;
    --nh)                 NH_CLI="$2";                           shift 2;;
    --verbose)            if [[ -n "${2-}" && $2 != -* ]]; then
                          verbose_level "$2";                    shift 2; else
                          verbose_level all;                     shift  ; fi ;;
    -v)                   verbose_level all;                     shift ;;
    -h|--help)            usage;                                 exit 0;;
    *)                    echo "Unknown arg: $1"; usage;         exit 1;;
  esac
done


  # Sanity checks
  [[ -n "$OBS_ID" ]] || { log "No OBS_ID specified"; usage; exit 1; }
  [[ -d "$BASE_DIR" ]] || die "Base dir not found: $BASE_DIR"




# ------------------------------------------------------------------------
# Start Logging
# ------------------------------------------------------------------------
log "Called arguments: $ORIGINAL_CALL"
log "Parsed input arguments:"
log "  Z       = ${Z_CLI:-}"
log "  NH      = ${NH_CLI:-}"
log ""




# ------------------------------------------------------------------------
# Load path variables
# ------------------------------------------------------------------------
source "${BASE_DIR}/scripts/resolve_paths.sh" --base-dir "$BASE_DIR" --obs-id "$OBS_ID" --verbose "$SAS_VERBOSE_LEVEL"

# Sanity check required files and scripts
[[ -d "$SUBTRACTION_DIR"  ]] || die "Subtraction dir not found: $SUBTRACTION_DIR"




# ------------------------------------------------------------------------
# Load or prompt for Z and NH
# ------------------------------------------------------------------------

# Load from spectra.env if it exists
  if [[ -s "$SPECTRA_ENV_FILE" ]]; then
    source "$SPECTRA_ENV_FILE"
  fi

  Z=""; NH=""; source_z=""; source_nh=""

  # CLI takes precedence if non-empty
  if [[ -n "${Z_CLI:-}" ]]; then
      Z="$Z_CLI"
      source_z="CLI"
  elif [[ -n "${Z_CONFIG:-}" ]]; then
      Z="$Z_CONFIG"
      source_z="Config"
  fi

  if [[ -n "${NH_CLI:-}" ]]; then
      NH="$NH_CLI"
      source_nh="CLI"
  elif [[ -n "${NH_CONFIG:-}" ]]; then
      NH="$NH_CONFIG"
      source_nh="Config"
  fi

  # Prompt user if missing
  if [[ -z "$Z" ]]; then
      read -rp "Enter cluster redshift (Z): " val
      Z="$val"
      source_z="Prompt"
  fi
  if [[ -z "$NH" ]]; then
      read -rp "Enter Galactic nH (1e22 cm^-2): " val
      NH="$val"
      source_nh="Prompt"
  fi

  log "Using Z=$Z ($source_z)"
  log "Using NH=$NH ($source_nh)"

  #  Offer to save to config (if from prompt or CLI)
  if [[ "$source_z" == "Prompt" || "$source_z" == "CLI" || "$source_nh" == "Prompt" || "$source_nh" == "CLI" ]]; then
      read -rp "Save Z=$Z and NH=$NH to ${SPECTRA_ENV_FILE#$BASE_DIR} for future runs? [y/n]: " reply
      if [[ $(norm_flag "$reply") == "yes" ]]; then
          mkdir -p "$CONFIG_DIR"
          cat > "$SPECTRA_ENV_FILE" <<EOF
export Z_CONFIG="$Z"
export NH_CONFIG="$NH"
EOF
          log "Saved Z and NH to ${SPECTRA_ENV_FILE#$BASE_DIR}"
      else
          log "Values not saved."
      fi
  fi




# ------------------------------------------------------------------------
# Run XSPEC
# ------------------------------------------------------------------------
cd "$SUBTRACTION_DIR"
MODEL_FILE="model_${OBS_ID}.xcm"

# -- Run automatically --
log "Launching XSPEC to fit spectra:"
log "  - Using:"
log "           Z=$Z"
log "          NH=$NH"
log "          0.3-10.0 keV"
log ""


PIPE=$(mktemp -u)
mkfifo "$PIPE"

xspec < "$PIPE" 2>&1 | tee -a "$LOG_FILE" &
{
  # -- Load files --
  echo "data 1:1 m1_final_grp.fits"
  echo "data 2:2 m2_final_grp.fits"
  echo "data 3:3 pn_final_grp.fits"

  # -- Select channels --
  echo "notice all"
  echo "ignore bad"
  echo "ignore 1-3:**-0.3 10.0-**"

  # -- Load base model --
  echo "@savexspec.xcm"
  echo "@${MODEL_FILE}"
  echo "newpar 1 1.0"
  echo "newpar 11 1.0"
  echo "newpar 2 $NH"
  echo "newpar 5 $Z"

  # -- Perform fit --
  echo "fit"
  echo "y"          # To continue fitting, if prompted
  echo "y"          # If not prompted, will display 'ambiguous command name'

  # -- Save under new model --
  echo "save model $MODEL_FILE"
  echo "y"

  # -- Display fitting params --
  echo "show par"
  echo "fit"
 
  # -- Plot results --
  echo "cpd /xserve"
  echo "setplot energy"
  echo "cpd ${QA_DIR}/xspec_ldata.ps/vcps" # Save
  echo "plot ldata ratio residual"
  echo "cpd /xserve"
  echo "plot ldata ratio residual" # Show

  # -- Close out --
  echo "cpd"
  echo "cpd"
  echo "exit"
  echo ""
  echo ""
} > "$PIPE"
wait
rm "$PIPE"



log "Model saved as ${MODEL_FILE}"
log "Images saved to ${QA_DIR#$BASE_DIR}/xspec_ldata.ps"

read -rp "Open interactive XSPEC session with model loaded? [y/n]: " resp
if [[ $(norm_flag "$resp") == "yes" ]]; then
  export MODEL_FILE="$MODEL_FILE"
  export Z="$Z"
  export NH="$NH"

  log ""
  log "Opening interactive XSPEC session with MODEL_FILE=${MODEL_FILE}, Z=${Z}, NH=${NH}..."
  log ""
  log "################################################################################"
  log "################################################################################"
  log ""
  log " Useful XSPEC commands:"
  log " Load data: data 1:1 m1_final_grp.fits"
  log "            data 2:2 m2_final_grp.fits"
  log "            data 3:3 pn_final_grp.fits"
  log " Ignore bad channels: "
  log "            notice all"
  log "            ignore bad"
  log " Ignore energy ranges: ignore 1-3:**-0.3 10.0-**"
  log " Load model: @savexspec.xcm"
  log " Set parameters: newpar 1 1.0; newpar 11 1.0; newpar 2 $NH; newpar 5 $Z"
  log " Save model: save model $MODEL_FILE"
  log " Show parameters: show par"
  log " Show errors: error 6; error 7"
  log " Plotting: "
  log "         cpd /xserve"
  log "         setplot energy"
  log "         plot ldata ratio residual       # View"
  log "         cpd QA_DIR/xspec_ldata.ps/vcps  # Save"
  log "         plot ldata ratio residual"
  log ""
  log "################################################################################"
  log "################################################################################"

SCRIPT_VERBOSE=2 #Set to 2 for debugging

#######################################################################
# The following section is problematic, probably uniquely suited to my
# machine, and its only purpose is to open a new terminal window. If
# this gives you issues, comment out the next line and uncomment the
# next. This will keep everything in the same terminal and should work.
#######################################################################


if command -v osascript >/dev/null 2>&1; then
# if [[ $SAS_VERBOSE_LEVEL == 3 ]]; then

    # Fresh terminal still needs the current environment. This builds a wrapper
    # script with values evaluated in the current shell, which is then run in 
    # the new terminal. It has a lot of trouble in setting up the conda env.
    cat > run_xspec_wrapper.sh <<EOF
    #!/usr/bin/env bash
    set -e

    echo "Shell: \$SHELL"
    echo "BASH_VERSION: \$BASH_VERSION"



    # Conda activation
    if [ -f "/usr/local/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/usr/local/Caskroom/miniconda/base/etc/profile.d/conda.sh"
        conda activate sas_env
    fi

    # LOG_DIR must come in before RESOLVE_PATHS sets a default
    export LOG_DIR="$LOG_DIR"
    
    # Source resolve_paths to set all required path variables
    source "$RESOLVE_PATHS_SH" --obs-id "$OBS_ID" --verbose "$SCRIPT_VERBOSE"

    # Initialize SAS environment
    source "$SET_SAS_VARIABLES_SH" --obs-id "$OBS_ID" --run-sasversion yes --verbose "$SCRIPT_VERBOSE"

    # Export Z and NH for use by the expect script
    export Z="$Z"
    export NH="$NH"
    export MODEL_FILE="$MODEL_FILE"

    cd "$SUBTRACTION_DIR"

    # Call the expect script
    exec "$SCRIPTS_DIR/run_xspec_interactive.exp" | tee -a "$LOG_DIR/xspec_interactive.log"
EOF

    # Make the wrapper script executable
    chmod +x run_xspec_wrapper.sh

    # Launch the wrapper in a new Terminal window
    osascript <<OSA
    tell application "Terminal"
        do script "cd '$(pwd)'; bash ./run_xspec_wrapper.sh"
        activate
    end tell
OSA

else
  # This will run in the current terminal, but log to a new file.
  "$SCRIPTS_DIR/run_xspec_interactive.exp" | tee -a "$LOG_DIR/xspec_interactive.log"
fi

fi




log "XSPEC fitting completed"
pop_tag "$TAG_xspec"