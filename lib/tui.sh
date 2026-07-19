#!/usr/bin/env bash
# whiptail wrappers with plain-prompt fallbacks (used when whiptail is
# missing, TUI_ACTIVE=0, or in tests).

TUI_ACTIVE=${TUI_ACTIVE:-1}
tui_available() { command -v whiptail >/dev/null 2>&1; }
_tui() { [ "$TUI_ACTIVE" -eq 1 ] && tui_available; }

_dims() { echo "20 72"; }   # rows cols; whiptail auto-grows lists

tui_msgbox() {
  local title="$1" text="$2"
  if _tui; then whiptail --title "$title" --msgbox "$text" $(_dims); else
    printf '\n== %s ==\n%b\n' "$title" "$text" >&2
  fi
}

tui_yesno() {
  local title="$1" text="$2"
  if _tui; then whiptail --title "$title" --yesno "$text" $(_dims); else
    local ans; printf '%b ' "$text"; read -r -p "[y/N] " ans || ans=""
    [[ "$ans" =~ ^[Yy] ]]
  fi
}

tui_input() {
  local title="$1" prompt="$2" def="$3"
  if _tui; then
    whiptail --title "$title" --inputbox "$prompt" $(_dims) "$def" 3>&1 1>&2 2>&3
  else
    local v; read -r -p "$prompt [$def]: " v || v=""
    echo "${v:-$def}"
  fi
}

# tui_menu TITLE PROMPT tag item [tag item...]
tui_menu() {
  local title="$1" prompt="$2"; shift 2
  if _tui; then
    whiptail --title "$title" --menu "$prompt" $(_dims) 10 "$@" 3>&1 1>&2 2>&3
    return
  fi
  local -a tags=() items=()
  while (($#)); do tags+=("$1"); items+=("$2"); shift 2; done
  printf '\n== %s ==\n' "$title" >&2
  local i; for i in "${!tags[@]}"; do printf '%2d) %s\n' "$((i+1))" "${items[$i]}" >&2; done
  local n; read -r -p "$prompt (1-${#tags[@]}): " n || n=""
  [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#tags[@]}" ] && echo "${tags[$((n-1))]}"
}

# tui_checklist TITLE PROMPT tag item state [...] — echoes selected tags
tui_checklist() {
  local title="$1" prompt="$2"; shift 2
  if _tui; then
    local out
    out=$(whiptail --title "$title" --separate-output --checklist "$prompt" $(_dims) 10 "$@" 3>&1 1>&2 2>&3) || return 1
    echo "$out" | tr '\n' ' '
    return
  fi
  local -a tags=() items=() states=()
  while (($#)); do tags+=("$1"); items+=("$2"); states+=("$3"); shift 3; done
  printf '\n== %s ==\n' "$title" >&2
  local i; for i in "${!tags[@]}"; do
    printf '%2d) [%s] %s\n' "$((i+1))" "$([ "${states[$i]}" = on ] && echo x || echo ' ')" "${items[$i]}" >&2
  done
  local line; read -r -p "$prompt (numbers to toggle, empty=keep): " line || line=""
  local n; for n in $line; do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    i=$((n-1)); [ "$i" -ge 0 ] && [ "$i" -lt "${#tags[@]}" ] || continue
    [ "${states[$i]}" = on ] && states[$i]=off || states[$i]=on
  done
  local out=""
  for i in "${!tags[@]}"; do [ "${states[$i]}" = on ] && out+="${tags[$i]} "; done
  echo "${out% }"
}

# tui_radiolist — same args as checklist; echoes single selected tag
tui_radiolist() {
  local title="$1" prompt="$2"; shift 2
  if _tui; then
    whiptail --title "$title" --radiolist "$prompt" $(_dims) 10 "$@" 3>&1 1>&2 2>&3
    return
  fi
  local -a tags=() items=() states=()
  while (($#)); do tags+=("$1"); items+=("$2"); states+=("$3"); shift 3; done
  local def=""; local i
  for i in "${!tags[@]}"; do [ "${states[$i]}" = on ] && def="${tags[$i]}"; done
  printf '\n== %s ==\n' "$title" >&2
  for i in "${!tags[@]}"; do
    printf '%2d) (%s) %s\n' "$((i+1))" "$([ "${states[$i]}" = on ] && echo '*' || echo ' ')" "${items[$i]}" >&2
  done
  local n; read -r -p "$prompt (number, empty=keep): " n || n=""
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#tags[@]}" ]; then
    echo "${tags[$((n-1))]}"
  else
    echo "$def"
  fi
}
