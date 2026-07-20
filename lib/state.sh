#!/usr/bin/env bash
# Selection state, data-file parsing, denylist, and profiles.

declare -gA SELECTIONS
declare -gA USER_TOUCHED

# Packages the removal engine must NEVER touch, even if listed in data files.
DENYLIST=(
  manjaro-system manjaro-keyring archlinux-keyring
  manjaro-alsa manjaro-gstreamer manjaro-pipewire
  'mhwd' 'mhwd-*' pacman pacman-mirrors
  sudo systemd base filesystem 'linux*' networkmanager
)

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

denylisted() {
  local pkg="$1" pat
  for pat in "${DENYLIST[@]}"; do
    # shellcheck disable=SC2053  # intentional glob match
    [[ "$pkg" == $pat ]] && return 0
  done
  return 1
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

# preset_apply recommended|minimal — bulk-populate SELECTIONS from the spec's
# preset table (see docs/superpowers/specs/2026-07-18-manjaro-sl-design.md).
preset_apply() {
  local preset="$1" name desc state
  local mode="${2:-reset}"
  _pset() {   # preset-scoped write honoring baseline mode
    if [ "$mode" = baseline ] && [ -n "${USER_TOUCHED[$1]:-}" ]; then return 0; fi
    state_set "$1" "$2"
  }
  # debloat-manjaro: on per file defaults; Minimal turns everything on
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) _pset "debloat/$name" "$state" ;;  # file defaults; pamac*/cosmetics/zsh stay off
      minimal)
        case "$name" in
          timeshift|timeshift-autosnap-manjaro|manjaro-zsh-config) _pset "debloat/$name" off ;;
          *) _pset "debloat/$name" on ;;
        esac ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/debloat-manjaro.list")
  # apps: recommended=off, minimal=on except warnings
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) _pset "debloat/$name" off ;;
      minimal)
        case "$name" in
          timeshift|timeshift-autosnap-manjaro) _pset "debloat/$name" off ;;
          *) _pset "debloat/$name" on ;;
        esac ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/debloat-apps.list")
  # printing/bluetooth: off in both presets
  while IFS='|' read -r name desc state; do _pset "debloat/$name" off; done \
    < <(cat <(list_entries "$REPO_ROOT/data/debloat-printing.list") \
            <(list_entries "$REPO_ROOT/data/debloat-bluetooth.list"))
  # recommended installs
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) _pset "install/$name" on ;;
      minimal)     _pset "install/$name" off ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/install-recommended.list")
  # tweaks: NetworkManager + fstrim on in both
  _pset "tweak/enable:NetworkManager.service" on
  _pset "tweak/enable:fstrim.timer" on
  # components + wallpaper
  local c; for c in dwm dmenu st slstatus doomfire; do _pset "component/$c" on; done
  case "$preset" in
    recommended) _pset dwm/wallpaper doomfire; _pset ly/animation doom
                 _pset ly/match_wallpaper on ;;
    minimal)     _pset dwm/wallpaper none ;;
  esac
  _pset ly/enable on
  # Old DE/DM removal: "checked" under Minimal, "prompt" (untouched) under
  # Recommended per the spec's preset table. Only mark entries that are
  # actually installed; guarded so this stays a no-op (and testable without
  # pacman) when debloat.sh isn't sourced or pacman isn't available.
  if [ "$preset" = minimal ] && declare -F debloat_installed_from >/dev/null && command -v pacman >/dev/null 2>&1; then
    local f
    for f in "$REPO_ROOT/data/de.list" "$REPO_ROOT/data/dm.list"; do
      while IFS='|' read -r name desc state; do _pset "debloat/$name" on; done < <(debloat_installed_from "$f")
    done
  fi
  unset -f _pset
}
