#!/usr/bin/env bash
###############################################################################
# helpers.sh – Shared utilities with structured logging & SAS verbosity
#
# Source this file in any pipeline script:
#   source /path/to/helpers.sh
# Then customise per‑script tag + verbosity:
#   LOG_TAG='[step2_1]'
#   verbose_level errors   # none | errors | all   (or 0/1/2 etc.)
#
# Provided symbols
#   log_info "msg"        – always logged, labelled INFO
#   log_error "msg"       – always logged, labelled ERROR
#   verbose_level <arg>   – set SAS verbosity (none/errors/all)
#   run_sas "cmd"         – run SAS/FTOOL obeying verbosity level
#   norm_flag, die, run_verbose (unchanged convenience)
###############################################################################



# -- Prevent multiple sourcing --
[[ -n ${HELPERS_SH_LOADED:-} ]] && return
HELPERS_SH_LOADED=1




# -------------------------------------------
# CLI helpers
# -------------------------------------------

# -- yes/true | no/false helper --
norm_flag() {
  local flag=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$flag" in
    yes|y|true|t)   echo yes  ;;
    no|n|false|f|"") echo no  ;;
    *) die "Invalid flag: $1" ;;
  esac
}


# -- verbosity helper -- 
verbose_flag() {
  local flag=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$flag" in
    yes|true|y|t|all|both|2|high) echo 2 ;;
    errors|err|1|mid)             echo 1 ;;
    no|false|f|n|none|0|low|'')   echo 0 ;;
    *) die "Invalid flag: $1" ;;
  esac
}



# -------------------------------------------
# Logging functions
# -------------------------------------------


# ANSI color codes
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PURPLE='\033[35m'
CYAN='\033[36m'
MAGENTA='\033[35m'
WHITE='\033[37m'


if [[ -t 2 ]]; then
  USE_COLOR=1
else
  USE_COLOR=0
fi


# -- Logging configuration --
LOG_TAG_DEFAULT="[pipeline]"           # caller can override after sourcing
LOG_TAG=${LOG_TAG:-$LOG_TAG_DEFAULT}
LOG_FILE=${LOG_FILE:-/dev/null} # caller may set before sourcing



_log_line() {
  local level="$1"      # -INFO-, -ERROR-, etc.
  local msg="$2"
  local date="$(date '+%F %T')"
  local tag="${LOG_TAG:-}"

  # Color selection
  local color_date="$CYAN"
  local color_info="$GREEN"
  local color_error="$RED"
  local color_warn="$YELLOW"
  local color_tag="$MAGENTA"
  local color_msg="$WHITE"
  local color_level
  case "$level" in
    -INFO-)  color_level="$color_info" ;;
    -ERROR-) color_level="$color_error" ;;
    -WARN-)  color_level="$color_warn" ;;
    *)       color_level="$WHITE" ;;
  esac

  # Terminal output (colored)
  if [[ "$USE_COLOR" -eq 1 ]]; then
    printf '%b%s%b %b%s%b %b%s%b %b%s%b\n' \
      "$color_date" "$date" "$RESET" \
      "$color_level" "$level" "$RESET" \
      "$color_tag" "$tag" "$RESET" \
      "$color_msg" "$msg" "$RESET" >&2
  else
    printf '%s %s %s %s\n' "$date" "$level" "$tag" "$msg" >&2
  fi

  # Log file (never colored)
  printf '%s %s %s %s\n' "$date" "$level" "$tag" "$msg" >>"$LOG_FILE"
}


# -- Logging commands --
log_info()  { _log_line -INFO-  "$*"; }
log()       { _log_line -INFO-  "$*"; }
log_error() { _log_line -ERROR- "$*"; }
log_warn()  { _log_line -WARN-  "$*"; }

die() { log_error "$*"; exit 1; }
require () { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }



# -- SAS checker -- 
# Checks if SAS routines are available (missing from SAS init, install, or if SAS changes)

require () {
  local cmd="$1"
  local obs_id="${2:-"$OBS_ID"}"                    # You need OBS_ID and SAS script, but they should be in env
  local sas_script="${3:-"$SET_SAS_VARIABLES_SH"}"
  VERB_LEVEL="${SAS_VERBOSE_LEVEL:-1}"

  # Try the command first
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -f "$sas_script" ]]; then
      local _require_cwd
      _require_cwd="$(pwd)"
      # Try to source SAS silently
      source "$sas_script" --obs-id "$obs_id" --build-ccf false --run-sasversion false --verbose 0  >/dev/null 2>&1 
      cd "$_require_cwd"
    fi
  fi
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required SAS command: $cmd"
  verbose_level "$VERB_LEVEL" # Restore if SAS initialization reset, prob not required anymore
}


# -- Tag management functions -- 
# May not need anymore if LOG_TAG gets consistently set, useful if sourcing

push_tag() {
    local tag="${1:-}"  # All this just to add some ****** padding
    local bar_len=60
    local text=" $tag "
    local pad_len=$(( (bar_len - ${#text}) / 2 ))
    local pad=$(printf '%*s' "$pad_len" '' | tr ' ' '*')
    local extra=$(( bar_len - (2 * pad_len) - ${#text} ))  # 0 or 1 if odd

    log ""
    LOG_TAG="${LOG_TAG:-}${tag}"
    export LOG_TAG # Ensures daughter inherits updated LOG_TAG
    log "${pad}${text}${pad}$( [[ $extra -gt 0 ]] && echo '*' )"
    
}

pop_tag() {
    local tag="${1:-}"
    [[ -n $tag && ${LOG_TAG:-} == *"$tag" ]] || return 
    local bar_len=60
    log "$(printf '%*s' "$bar_len" '' | tr ' ' '*')"
    LOG_TAG="${LOG_TAG::${#LOG_TAG}-${#tag}}"
    export LOG_TAG # Ensures parent inherits updated LOG_TAG
    log ""
}




# -------------------------------------------
# Verbosity management functions
# -------------------------------------------

# -- Verbosity setter --
# 0 = none   (Suppress SAS stdout+stderr)
# 1 = errors (Only SAS stderr logged as ERROR)
# 2 = all    (SAS stdout->INFO, stderr->ERROR)

SAS_VERBOSE_LEVEL=1   # Default

verbose_level() {
  SAS_VERBOSE_LEVEL=$(verbose_flag "$1") || exit 1
}

# ─- SAS verbosity control --
# Shell sensitive, run with bash

# Colored text ANSI codes
# GREEN='\033[32m'
# RED='\033[31m'
# RESET='\033[0m'

run_verbose() {
    local cmd="$1"
    local date_str="$(date '+%F %T')"
    # Pattern to strip ANSI color
    local strip_ansi="s/\x1B\[[0-9;]*[mK]//g"
    case $SAS_VERBOSE_LEVEL in
        0)
            eval "$cmd" >/dev/null 2>&1
            ;;
        1)
            eval "$cmd" \
                > /dev/null \
                2> >(sed $'s|^|\x1b[36m'"$date_str"' \x1b[0m\x1b[31m-ERROR-\x1b[0m \x1b[35m'"$LOG_TAG"'\x1b[0m |; s|$|\x1b[0m|' \
                        | tee >(sed "$strip_ansi" >> "$LOG_FILE") >&2)
            ;;
        2)
            eval "$cmd" \
                > >(sed $'s|^|\x1b[36m'"$date_str"' \x1b[0m\x1b[32m-INFO-\x1b[0m \x1b[35m'"$LOG_TAG"'\x1b[0m |; s|$|\x1b[0m|' \
                        | tee >(sed "$strip_ansi" >> "$LOG_FILE") >&2) \
                2> >(sed $'s|^|\x1b[36m'"$date_str"' \x1b[0m\x1b[31m-ERROR-\x1b[0m \x1b[35m'"$LOG_TAG"'\x1b[0m |; s|$|\x1b[0m|' \
                        | tee >(sed "$strip_ansi" >> "$LOG_FILE") >&2)
            ;;
    esac
}


# I started with run_sas and changed to run_verbose, but there may be some run_sas commands hiding
run_sas() { run_verbose "$@"; }




# -------------------------------------------
# SAS Helpers
# -------------------------------------------

# -- Accessor functions --
evt_of()    { case "$1" in m1) echo "$ANALYSIS_DIR/mos1S001.fits";;        m2) echo "$ANALYSIS_DIR/mos2S002.fits";;        pn) echo "$ANALYSIS_DIR/pnS003.fits";;        *)  die "Unknown detector: $1";; esac; }
allevc_of() { case "$1" in m1) echo "$ANALYSIS_DIR/mos1S001-allevc.fits";; m2) echo "$ANALYSIS_DIR/mos2S002-allevc.fits";; pn) echo "$ANALYSIS_DIR/pnS003-allevc.fits";; *)  die "Unknown detector: $1";; esac; }
blank_of()  { case "$1" in m1) echo "$M1_DIR/m1_blank.fits";;              m2) echo "$M2_DIR/m2_blank.fits";;              pn) echo "$PN_DIR/pn_blank.fits";;            *)  die "Unknown detector: $1";; esac; }
rate_of()   { case "$1" in m1) echo "$MOS1_RATE";;                         m2) echo "$MOS2_RATE";;                         pn) echo "$PN_RATE";;                         *)  die "Unknown detector: $1";; esac; }
ccds_of()   { case "$1" in m1) echo "$EXCLUDE_CCDS_M1";;                   m2) echo "$EXCLUDE_CCDS_M2";;                   pn) echo "";;                                 *)  die "Unknown detector: $1";; esac; }
dir_of()    { case "$1" in m1) echo "$M1_DIR";;                            m2) echo "$M2_DIR";;                            pn) echo "$PN_DIR";; esac; }
name_of()   { case "$1" in m1) echo "mos1S001";;                           m2) echo "mos2S002";;                           pn) echo "pnS003";; esac; }


ensure_sas_env() {
  # Ensure SAS environment is loaded for current observation
  local sas_script="${SET_SAS_VARIABLES_SH:-}"
  local obs_id="${OBS_ID:-}"
  if ! command -v evselect >/dev/null 2>&1; then
    log "SAS environment not loaded; sourcing: $sas_script"

    [[ -f "$sas_script" ]] || die "Could not find SAS environment script at $sas_script"
    source "$sas_script" --obs-id "$obs_id" >/dev/null 2>&1

    if ! command -v evselect >/dev/null 2>&1; then
      die "SAS environment still not available after sourcing. Aborting."
    
    fi
    log "SAS environment loaded successfully."
  fi
}


header_val() {
    local file="$1" key="$2"
    fitsheader "$file" -e 0 \
    | awk -F"= " -v k="$key" 'toupper($1) ~ ("^" toupper(k) "[ \t]*$") {
        gsub(/'\''/,"",$2)       # remove single quotes
        gsub(/\/.*/,"",$2)       # strip FITS comment
        gsub(/^[ \t]+|[ \t]+$/,"",$2)  # trim whitespace
        print $2
        exit
    }'
}


ensure_blank_for_evt() {
    local det="$1"
    local evf
    log "Ensuring blank sky for detector: $det"
    evf="$(evt_of "$det")"
    [[ -f "$evf" ]] || die "Missing event file: $evf"
    local filter_raw filter
    filter_raw="$(header_val "$evf" FILTER)"
    [[ -z "$filter_raw" ]] && die "FILTER keyword missing from $evf"
    filter="$(filter_normalize "$filter_raw")"
    ensure_blank "$det" "$filter"
}

filter_normalize() {
    # Usage: filter_normalize "filter_string"
    local filter="$1"
    filter=$(echo "$filter" | tr '[:upper:]' '[:lower:]')
    filter=$(echo "$filter" | sed 's/[0-9]$//')
    [[ "$filter" == "medium" ]] && filter="med"
    echo "$filter"
}

ensure_blank() {
    local det="$1" filter="$2"
    local dst src tmp
    case "$det" in
        m1) dst="$(blank_of m1)"; src="${BLANK_SKY_DIR}/m1_blank_${filter}.fits";;
        m2) dst="$(blank_of m2)"; src="${BLANK_SKY_DIR}/m2_blank_${filter}.fits";;
        pn) dst="$(blank_of pn)"; src="${BLANK_SKY_DIR}/pn_blank_${filter}.fits";;
        *)  die "Unknown detector for ensure_blank: $det";;
    esac
    if [[ ! -f "$dst" ]]; then
        if [[ ! -f "$src" ]]; then
            die "Missing blank sky file: $src"
        fi
        tmp="${dst}.copying"
        log "Copying blank sky: $src -> $dst"
        cp "$src" "$tmp" || { rm -f "$tmp"; die "Failed to copy $src to $dst"; }
        mv "$tmp" "$dst"
        log "Blank sky copy complete: $dst"
    fi
}

load_regions(){
  local regions_env="${CONFIG_DIR}/regions.env"

  # Use existing regions.env if it exists and is non-empty
  if [[ -s "$regions_env" ]]; then
    set -a; . "$regions_env"; set +a
    return 0
  fi

  # Fall back to running make_regions.sh
  [[ -f "$MAKE_REGIONS_SH" ]] || die "No regions.env and no $MAKE_REGIONS_SH"

  log "No regions.env found - running make_regions.sh..."
  source "$MAKE_REGIONS_SH" --obs-id "$OBS_ID" --base-dir "$BASE_DIR" --verbose "$SAS_VERBOSE_LEVEL" \
    || die "make_regions.sh failed"

  # Ensure the env file was created
  [[ -s "$regions_env" ]] || die "make_regions.sh did not produce $regions_env"

  set -a; . "$regions_env"; set +a
}

get_ccds() {
  local cli_val="$1"      # CLI override (may be empty)
  local env_var="$2"      # Env variable name (e.g. EXCLUDE_CCDS_M1)
  local config_file="$3"  # Path to config file (e.g. $CONFIG_DIR/ccds.env)
  local det="$4"          # Detector tag ("m1", "m2", "pn")
  local ccds val source

  case "$det" in
    m1) ccds_var="EXCLUDE_CCDS_M1";;
    m2) ccds_var="EXCLUDE_CCDS_M2";;
    pn) return 0;;  # PN never has excluded CCDs
    *)  die "Unknown detector: $det";;
  esac

  # CLI takes precedence if non-empty
  if [[ -n "$cli_val" ]]; then
    ccds="$cli_val"
    source="CLI"

  # ENV var takes precedence if non-empty
  elif [[ -n "${!env_var:-}" ]]; then
    ccds="${!env_var}"
    source="ENV"

  # Config file (if exists and has a value — including explicit empty)
  elif [[ -s "$config_file" ]]; then
    set -a; . "$config_file"; set +a
    if [[ -v ${env_var} ]]; then
      ccds="${!env_var}"
      source="Config"
    fi
  fi

  # If all else fails, use emanom
  if [[ -z "${ccds+set}" ]]; then
    local evf

    evf="$(evt_of "$det")"
    [[ -f "$evf" ]] || die "Missing event file for $det: $evf"

    require emanom

    log "Running emanom for $det..."
    mkdir -p "$QA_DIR"
    local logf="${QA_DIR}/${det}_anom.log"
    emanom eventfile="$evf" keepcorner=no writelog=no > "$logf" 2>&1 || true

    # Parse CCD status lines and log them

    awk_output=$(awk -v det="$det" '
      / CCD:/ && /Status:/ {
        ccd_num = $4
        status  = $NF
        printf "STATUS: [%s] CCD %d Status: %s\n", det, ccd_num, status
        if (status == "O") {
          out = (out ? out "," : "") ccd_num
        }
      }
      END { print out }
    ' "$logf")

    bad_ccds=""
    while IFS= read -r line; do
      if [[ "$line" == STATUS:* ]]; then
        # Remove "STATUS: " prefix and send through logger
        log_info "${line#STATUS: }"
      elif [[ -n "$line" ]]; then
        bad_ccds="$line"
      fi
    done <<< "$awk_output"
    ccds="$bad_ccds"

    # Save to config file
    mkdir -p "$(dirname "$config_file")"
    { [[ -f "$config_file" ]] && grep -v "^${env_var}=" "$config_file" || true; \
      echo "${env_var}=\"${ccds}\""; \
    } > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    source="Emanom"
  
  fi

  log "Using $env_var='$ccds' ($source)"
  echo "$ccds"
}

get_rate() {
  local cli_val="$1"      # CLI override (may be empty)
  local env_var="$2"      # Env variable name (e.g. MOS1_RATE)
  local config_file="$3"  # Path to config file (e.g. $CONFIG_DIR/rates.env)
  local default="$4"      # Default value to prompt user
  local rate val source reply

  # CLI takes precedence if non-empty
  if [[ -n "$cli_val" ]]; then
    rate="$cli_val"
    source="CLI"

  # ENV var takes precedence if non-empty
  elif [[ -n "${!env_var:-}" ]]; then
    rate="${!env_var}"
    source="ENV"

  # Config file (if exists and has non-empty value)
  elif [[ -f "$config_file" ]]; then
    val=$(grep -E "^export[[:space:]]+$env_var=" "$config_file" | sed -E "s/^export[[:space:]]+$env_var=[\"']?([^\"']*)[\"']?/\1/")
    if [[ -n "$val" ]]; then
      rate="$val"
      source="Config"
    fi
  fi

  # If all else fails, prompt user
  if [[ -z "${rate:-}" ]]; then
    read -rp "Enter background flare threshold for $env_var [$default]: " val
    rate="${val:-$default}"

    log "You entered: $rate for $env_var"

    read -rp "Save this value to $config_file for future runs? [y/n]: " reply

    if [[ $(norm_flag "$reply") == "yes" ]]; then
      mkdir -p "$(dirname "$config_file")"

      if [[ -f "$config_file" ]]; then
        grep -v "^export $env_var=" "$config_file" > "${config_file}.tmp" || true
        mv "${config_file}.tmp" "$config_file"
      fi

      echo "export $env_var=\"$rate\"" >> "$config_file"
      log "Saved $env_var=$rate to $config_file"
    fi
    source="Prompt"

  fi
  log "Using $env_var=$rate ($source)"
  echo "$rate"
}