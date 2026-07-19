#!/usr/bin/env bash
# Interactive configuration for slstatus, dwm, and misc dotfiles.

configure_slstatus_interface() {
  local config_file="${REPO_ROOT}/slstatus/config.h"
  # Fallback to config.def.h if config.h doesn't exist
  if [ ! -f "$config_file" ]; then
    config_file="${REPO_ROOT}/slstatus/config.def.h"
  fi
  local current_iface
  current_iface=$(sed -n 's/.*netspeed_rx.*"\([^"]*\)".*/\1/p' "$config_file" | head -n1)
  current_iface=${current_iface:-unknown}

  local chosen_iface="$SLSTATUS_INTERFACE"
  if [ -z "$chosen_iface" ] && [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
    echo
    echo "Choose network interface for slstatus netspeed widgets (current: ${current_iface}):"

    # Get list of network interfaces
    local interfaces=()
    if command -v ip >/dev/null 2>&1; then
      # Use ip command (preferred on modern systems)
      while read -r iface; do
        if [ -n "$iface" ] && [[ "$iface" != "lo" ]]; then
          interfaces+=("$iface")
        fi
      done < <(ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v '^lo$')
    elif command -v ifconfig >/dev/null 2>&1; then
      # Fallback to ifconfig
      while read -r iface; do
        if [ -n "$iface" ] && [[ "$iface" != "lo" ]]; then
          interfaces+=("$iface")
        fi
      done < <(ifconfig -a | grep -E '^[a-zA-Z]' | awk '{print $1}' | sed 's/://' | grep -v '^lo$')
    else
      echo "Warning: Neither 'ip' nor 'ifconfig' found. Cannot detect network interfaces." >&2
      read -r -p "Enter network interface manually: " chosen_iface || chosen_iface=""
    fi

    if [ ${#interfaces[@]} -gt 0 ]; then
      # Display interface menu
      local i=1
      for iface in "${interfaces[@]}"; do
        echo "${i}) ${iface}"
        ((i++))
      done
      echo "${i}) Custom interface"
      echo "$((i+1))) Keep current (${current_iface})"
      echo

      while true; do
        read -r -p "Enter your choice (1-$((i+1))): " choice || choice=""
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((i+1)) ]; then
          if [ "$choice" -eq "$i" ]; then
            # Custom interface option
            read -r -p "Enter custom interface name: " custom_iface || custom_iface=""
            if [ -n "$custom_iface" ]; then
              chosen_iface="$custom_iface"
              break
            else
              echo "No interface entered, keeping current: ${current_iface}" >&2
              chosen_iface="$current_iface"
              break
            fi
          elif [ "$choice" -eq $((i+1)) ]; then
            # Keep current option
            chosen_iface="$current_iface"
            break
          else
            # Selected interface from list
            chosen_iface="${interfaces[$((choice-1))]}"
            break
          fi
        elif [ -n "$choice" ]; then
          echo "Invalid choice. Please enter a number between 1 and $((i+1))." >&2
        else
          echo "No choice entered, keeping current: ${current_iface}" >&2
          chosen_iface="$current_iface"
          break
        fi
      done
    fi
  fi

  if [ -n "$chosen_iface" ]; then
    require_command python3 "Python 3 is needed to update slstatus/config.h."
    python3 - "$config_file" "$chosen_iface" <<'PY'
import re
import sys

path, iface = sys.argv[1:3]
with open(path, encoding='utf-8') as fh:
    data = fh.read()

pattern = re.compile(r'(\{\s*netspeed_(?:rx|tx)\s*,\s*"[^"]*",\s*")([^"]*)(".*)')

def repl(match):
    return f"{match.group(1)}{iface}{match.group(3)}"

new_data, count = pattern.subn(repl, data)
if count == 0:
    sys.stderr.write('Warning: could not locate netspeed entries to update.\n')
else:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(new_data)
PY
    echo "Updated slstatus network interface to '${chosen_iface}'."
  fi
}

configure_slstatus_battery() {
  local config_file="${REPO_ROOT}/slstatus/config.h"
  # Fallback to config.def.h if config.h doesn't exist
  if [ ! -f "$config_file" ]; then
    config_file="${REPO_ROOT}/slstatus/config.def.h"
  fi
  local desired_state="$1"

  if [ -z "$desired_state" ] && [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
    if prompt_yes_no "Enable battery status in slstatus?" "n"; then
      desired_state="enable"
    else
      desired_state="disable"
    fi
  elif [ -z "$desired_state" ]; then
    desired_state="disable"
  fi

  if [ "$desired_state" = "enable" ]; then
    require_command python3 "Python 3 is needed to update slstatus/config.h."
    python3 - "$config_file" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    lines = fh.readlines()

updated = []
for line in lines:
    stripped = line.lstrip()
    indent = line[: len(line) - len(stripped)]
    if stripped.startswith('//{ battery_perc'):
        updated.append(f"{indent}{stripped[2:]}")
    else:
        updated.append(line)

with open(path, 'w', encoding='utf-8') as fh:
    fh.writelines(updated)
PY
    echo "Enabled slstatus battery widget (uses BAT0 by default)."
  else
    require_command python3 "Python 3 is needed to update slstatus/config.h."
    python3 - "$config_file" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    lines = fh.readlines()

updated = []
for line in lines:
    stripped = line.lstrip()
    indent = line[: len(line) - len(stripped)]
    if stripped.startswith('{ battery_perc'):
        updated.append(f"{indent}//{stripped}")
    else:
        updated.append(line)

with open(path, 'w', encoding='utf-8') as fh:
    fh.writelines(updated)
PY
    echo "Disabled slstatus battery widget."
  fi
}

configure_dwm_bar_color() {
  local config_file="${REPO_ROOT}/dwm/config.h"
  # Fallback to config.def.h if config.h doesn't exist
  if [ ! -f "$config_file" ]; then
    config_file="${REPO_ROOT}/dwm/config.def.h"
  fi
  local current_color
  current_color=$(sed -n 's/.*col_accent\[\].*= "\([^"]*\)";/\1/p' "$config_file" | head -n1)
  current_color=${current_color:-#000000}

  local chosen_color="$BAR_COLOR"
  if [ -z "$chosen_color" ] && [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
    echo
    echo "Choose a color for the dwm selected bar background (current: ${current_color}):"
    echo "1) Solarized Blue    #268bd2"
    echo "2) Solarized Cyan    #2aa198"
    echo "3) Solarized Green   #859900"
    echo "4) Solarized Yellow  #b58900"
    echo "5) Solarized Orange  #cb4b16"
    echo "6) Solarized Red     #dc322f"
    echo "7) Solarized Magenta #d33682"
    echo "8) Solarized Violet  #6c71c4"
    echo "9) Nord Blue         #5e81ac"
    echo "10) Nord Red         #bf616a"
    echo "11) Nord Green       #a3be8c"
    echo "12) Nord Yellow      #ebcb8b"
    echo "13) Gruvbox Blue     #458588"
    echo "14) Gruvbox Red      #cc241d"
    echo "15) Gruvbox Green    #98971a"
    echo "16) Custom hex color"
    echo "17) Keep current     ${current_color}"
    echo

    while true; do
      read -r -p "Enter your choice (1-17): " choice || choice=""
      case "$choice" in
        1) chosen_color="#268bd2"; break ;;
        2) chosen_color="#2aa198"; break ;;
        3) chosen_color="#859900"; break ;;
        4) chosen_color="#b58900"; break ;;
        5) chosen_color="#cb4b16"; break ;;
        6) chosen_color="#dc322f"; break ;;
        7) chosen_color="#d33682"; break ;;
        8) chosen_color="#6c71c4"; break ;;
        9) chosen_color="#5e81ac"; break ;;
        10) chosen_color="#bf616a"; break ;;
        11) chosen_color="#a3be8c"; break ;;
        12) chosen_color="#ebcb8b"; break ;;
        13) chosen_color="#458588"; break ;;
        14) chosen_color="#cc241d"; break ;;
        15) chosen_color="#98971a"; break ;;
        16)
          while true; do
            read -r -p "Enter custom hex color (e.g., #ff0000): " custom_color || custom_color=""
            if [[ "$custom_color" =~ ^#[0-9a-fA-F]{6}$ ]]; then
              chosen_color="$custom_color"
              break
            elif [ -n "$custom_color" ]; then
              echo "Invalid format. Please use format like #ff0000 (6 hex digits after #)." >&2
            else
              echo "No color entered, keeping current: ${current_color}" >&2
              chosen_color="$current_color"
              break
            fi
          done
          break
          ;;
        17) chosen_color="$current_color"; break ;;
        *)
          if [ -n "$choice" ]; then
            echo "Invalid choice. Please enter a number between 1-17." >&2
          else
            echo "No choice entered, keeping current: ${current_color}" >&2
            chosen_color="$current_color"
            break
          fi
          ;;
      esac
    done
  fi

  if [ -n "$chosen_color" ]; then
    require_command python3 "Python 3 is needed to update dwm/config.h."
    python3 - "$config_file" "$chosen_color" <<'PY'
import re
import sys

path, color = sys.argv[1:3]
with open(path, encoding='utf-8') as fh:
    data = fh.read()

pattern = re.compile(r'(static const char col_accent\[\]\s*=\s*")([^"]+)(";)')
if not pattern.search(data):
    sys.stderr.write('Warning: could not locate col_accent definition.\n')
else:
    new_data = pattern.sub(rf"\1{color}\3", data, count=1)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(new_data)
PY
    echo "Updated dwm selected bar color to '${chosen_color}'."
  fi
}

configure_dwm_modkey() {
  local config_file="${REPO_ROOT}/dwm/config.h"
  # Fallback to config.def.h if config.h doesn't exist
  if [ ! -f "$config_file" ]; then
    config_file="${REPO_ROOT}/dwm/config.def.h"
  fi

  local current_modkey
  if grep -q '#define MODKEY Mod4Mask' "$config_file" 2>/dev/null; then
    current_modkey="super"
  elif grep -q '#define MODKEY Mod1Mask' "$config_file" 2>/dev/null; then
    current_modkey="alt"
  else
    current_modkey="alt"
  fi

  local chosen_modkey="$MODKEY_CHOICE"
  if [ -z "$chosen_modkey" ] && [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
    echo
    echo "Choose modkey for dwm (current: ${current_modkey}):"
    echo "1) Super key (Windows/Command key)"
    echo "2) Alt key"
    echo "3) Keep current (${current_modkey})"
    echo

    while true; do
      read -r -p "Enter your choice (1-3): " choice || choice=""
      case "$choice" in
        1) chosen_modkey="super"; break ;;
        2) chosen_modkey="alt"; break ;;
        3) chosen_modkey="$current_modkey"; break ;;
        *)
          if [ -n "$choice" ]; then
            echo "Invalid choice. Please enter a number between 1-3." >&2
          else
            echo "No choice entered, keeping current: ${current_modkey}" >&2
            chosen_modkey="$current_modkey"
            break
          fi
          ;;
      esac
    done
  elif [ -z "$chosen_modkey" ]; then
    chosen_modkey="$current_modkey"
  fi

  if [ -n "$chosen_modkey" ]; then
    require_command python3 "Python 3 is needed to update dwm config.h."

    local modkey_value
    if [ "$chosen_modkey" = "super" ]; then
      modkey_value="Mod4Mask"
    else
      modkey_value="Mod1Mask"
    fi

    python3 - "$config_file" "$modkey_value" <<'PY'
import re
import sys

path, modkey = sys.argv[1:3]
with open(path, encoding='utf-8') as fh:
    data = fh.read()

pattern = re.compile(r'(#define\s+MODKEY\s+)(Mod[14]Mask)')
if not pattern.search(data):
    sys.stderr.write('Warning: could not locate MODKEY definition.\n')
else:
    new_data = pattern.sub(rf"\1{modkey}", data, count=1)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(new_data)
PY
    echo "Updated dwm modkey to '${chosen_modkey}' (${modkey_value})."
  fi
}

setup_misc_files() {
  local xinit_source="${REPO_ROOT}/misc0/xinitrc-config.txt"
  local xinit_target="$HOME/.xinitrc"
  local desktop_source="${REPO_ROOT}/misc0/dwm.desktop"
  local desktop_target="/usr/share/xsessions/dwm.desktop"

  local should_copy_xinit="$COPY_XINIT"
  if [ -z "$should_copy_xinit" ]; then
    if [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
      if prompt_yes_no "Copy xinitrc helper to ${xinit_target}?" "y"; then
        should_copy_xinit="yes"
      else
        should_copy_xinit="no"
      fi
    else
      should_copy_xinit="no"
    fi
  fi

  if [ "$should_copy_xinit" = "yes" ]; then
    # Must be executable: the dwm.desktop session entry runs it as a command.
    copy_with_backup "$xinit_source" "$xinit_target" "no" "755"
  fi

  local should_copy_desktop="$COPY_DESKTOP"
  if [ -z "$should_copy_desktop" ]; then
    if [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
      if prompt_yes_no "Copy dwm.desktop to ${desktop_target}? (requires root)" "y"; then
        should_copy_desktop="yes"
      else
        should_copy_desktop="no"
      fi
    else
      should_copy_desktop="no"
    fi
  fi

  if [ "$should_copy_desktop" = "yes" ]; then
    copy_with_backup "$desktop_source" "$desktop_target" "yes"
  fi
}
