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
