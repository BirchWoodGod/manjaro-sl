#!/usr/bin/env bash
# Selection state, data-file parsing, denylist, and profiles.

declare -gA SELECTIONS

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
  # debloat-manjaro: on per file defaults; Minimal turns everything on
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) state_set "debloat/$name" "$state" ;;  # file defaults; pamac*/cosmetics/zsh stay off
      minimal)
        case "$name" in
          timeshift|timeshift-autosnap-manjaro|manjaro-zsh-config) state_set "debloat/$name" off ;;
          *) state_set "debloat/$name" on ;;
        esac ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/debloat-manjaro.list")
  # apps: recommended=off, minimal=on except warnings
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) state_set "debloat/$name" off ;;
      minimal)
        case "$name" in
          timeshift|timeshift-autosnap-manjaro) state_set "debloat/$name" off ;;
          *) state_set "debloat/$name" on ;;
        esac ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/debloat-apps.list")
  # printing/bluetooth: off in both presets
  while IFS='|' read -r name desc state; do state_set "debloat/$name" off; done \
    < <(cat <(list_entries "$REPO_ROOT/data/debloat-printing.list") \
            <(list_entries "$REPO_ROOT/data/debloat-bluetooth.list"))
  # recommended installs
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) state_set "install/$name" on ;;
      minimal)     state_set "install/$name" off ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/install-recommended.list")
  # tweaks: NetworkManager + fstrim on in both
  state_set "tweak/enable:NetworkManager.service" on
  state_set "tweak/enable:fstrim.timer" on
  # components + wallpaper
  local c; for c in dwm dmenu st slstatus doomfire; do state_set "component/$c" on; done
  case "$preset" in
    recommended) state_set dwm/wallpaper doomfire; state_set ly/animation doom
                 state_set ly/match_wallpaper on ;;
    minimal)     state_set dwm/wallpaper none ;;
  esac
  state_set ly/enable on
}
