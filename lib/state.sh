#!/usr/bin/env bash
# Selection state, data-file parsing, and profiles.

declare -gA SELECTIONS
declare -gA USER_TOUCHED

state_set() { SELECTIONS["$1"]="$2"; }
state_get() { echo "${SELECTIONS[$1]:-off}"; }
state_on()  { [ "${SELECTIONS[$1]:-off}" = "on" ]; }

# user_set — state_set for INTERACTIVE screens: records the key as an
# explicit user choice so baseline presets won't overwrite it.
user_set() { state_set "$1" "$2"; USER_TOUCHED["$1"]=1; }

# list_entries FILE — echo "name|desc|state" lines, comments/blanks stripped.
list_entries() {
  grep -Ev '^\s*(#|$)' "$1" || true
}

profile_save() {
  local f="$1" key
  mkdir -p "$(dirname "$f")"
  : > "$f"
  for key in "${!SELECTIONS[@]}"; do
    printf '%s=%s\n' "$key" "${SELECTIONS[$key]}" >> "$f"
  done
}

profile_load() {
  local f="$1" line
  [ -f "$f" ] || return 1
  while IFS='=' read -r key val; do
    [ -n "$key" ] && SELECTIONS["$key"]="$val"
  done < "$f"
}

# preset_apply recommended|minimal — bulk-populate SELECTIONS. Both presets
# build the full suckless component set with a Ly display manager; they
# differ only in the extra recommended software and the desktop look:
#   recommended — install the recommended package list, doomfire wallpaper +
#                 doom login animation kept in sync.
#   minimal     — no extra recommended software, no wallpaper/animation.
preset_apply() {
  local preset="$1" name desc state
  local mode="${2:-reset}"
  _pset() {   # preset-scoped write honoring baseline mode
    if [ "$mode" = baseline ] && [ -n "${USER_TOUCHED[$1]:-}" ]; then return 0; fi
    state_set "$1" "$2"
  }
  # recommended installs
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) _pset "install/$name" on ;;
      minimal)     _pset "install/$name" off ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/install-recommended.list")
  # components + wallpaper
  local c; for c in dwm dmenu st slstatus doomfire; do _pset "component/$c" on; done
  case "$preset" in
    recommended) _pset dwm/wallpaper doomfire; _pset ly/animation doom
                 _pset ly/match_wallpaper on ;;
    minimal)     _pset dwm/wallpaper none ;;
  esac
  _pset ly/enable on
  unset -f _pset
}
