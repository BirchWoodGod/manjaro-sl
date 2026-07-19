#!/usr/bin/env bash
# Old DE/DM detection/removal and Ly display manager configuration.

# Known display managers (excluding ly, which we install)
KNOWN_DISPLAY_MANAGERS=(
  gdm
  sddm
  lightdm
  lxdm
  slim
  entrance
  lemurs
  greetd
  emptty
  tbsm
)

# Known desktop environments / window managers (excluding dwm)
KNOWN_DESKTOP_ENVIRONMENTS=(
  gnome
  plasma
  xfce4
  cinnamon
  mate
  budgie-desktop
  deepin
  lxqt
  lxde-common
  i3-wm
  sway
  openbox
  bspwm
  herbstluftwm
  awesome
  qtile
  hyprland
  xmonad
  fluxbox
  icewm
)

detect_and_remove_old_de() {
  if [ "$REMOVE_OLD_DE" = "no" ]; then
    echo "Skipping old display manager / desktop environment removal."
    return
  fi

  if ! command -v pacman >/dev/null 2>&1; then
    echo "Warning: pacman not found; skipping old DE/DM detection." >&2
    return
  fi

  # --- Detect installed display managers ---
  local installed_dms=()
  for dm in "${KNOWN_DISPLAY_MANAGERS[@]}"; do
    if pacman -Qi "$dm" >/dev/null 2>&1; then
      installed_dms+=("$dm")
    fi
  done

  # --- Detect installed desktop environments ---
  local installed_des=()
  for de in "${KNOWN_DESKTOP_ENVIRONMENTS[@]}"; do
    if pacman -Qi "$de" >/dev/null 2>&1; then
      installed_des+=("$de")
    fi
  done

  if [ ${#installed_dms[@]} -eq 0 ] && [ ${#installed_des[@]} -eq 0 ]; then
    echo "No other display managers or desktop environments detected."
    return
  fi

  echo
  echo "==> Detected existing display managers / desktop environments"
  if [ ${#installed_dms[@]} -gt 0 ]; then
    echo "  Display managers: ${installed_dms[*]}"
  fi
  if [ ${#installed_des[@]} -gt 0 ]; then
    echo "  Desktop environments: ${installed_des[*]}"
  fi
  echo

  # In non-interactive mode, only remove if --remove-de was explicitly passed
  if [ "$ACCEPT_DEFAULTS" -eq 1 ] && [ "$REMOVE_OLD_DE" != "yes" ]; then
    echo "Non-interactive mode: keeping existing display managers and desktop environments."
    echo "Use --remove-de to remove them automatically."
    return
  fi

  local should_remove="$REMOVE_OLD_DE"
  if [ -z "$should_remove" ]; then
    if prompt_yes_no "Would you like to remove these before setting up dwm + Ly?" "n"; then
      should_remove="yes"
    else
      should_remove="no"
    fi
  fi

  if [ "$should_remove" != "yes" ]; then
    echo "Keeping existing display managers and desktop environments."
    return
  fi

  # --- Disable old display manager services (but do NOT stop them yet) ---
  # Stopping the active DM would kill the user's graphical session immediately,
  # leaving a black screen before dwm + Ly are ready.  We only disable the
  # services here so they won't start on next boot.  The running session stays
  # alive until the user reboots (at which point Ly will take over).
  for dm in "${installed_dms[@]}"; do
    echo "Disabling ${dm} service (will take effect on next boot)..."
    run_with_privilege systemctl disable "${dm}.service" 2>/dev/null || true
  done

  # --- Build the combined removal list ---
  local to_remove=()
  to_remove+=("${installed_dms[@]}")
  to_remove+=("${installed_des[@]}")

  echo
  echo "The following packages will be removed (with unused dependencies):"
  echo "  ${to_remove[*]}"
  echo

  # Final confirmation in interactive mode (unless --remove-de was passed)
  if [ "$ACCEPT_DEFAULTS" -eq 0 ] && [ "$REMOVE_OLD_DE" != "yes" ]; then
    if ! prompt_yes_no "Proceed with removal?" "n"; then
      echo "Removal cancelled."
      return
    fi
  fi

  local pacman_cmd=(pacman -Rns)
  if [ "$ACCEPT_DEFAULTS" -eq 1 ]; then
    pacman_cmd+=(--noconfirm)
  fi
  pacman_cmd+=("${to_remove[@]}")

  echo "Removing: ${to_remove[*]}"
  if run_with_privilege "${pacman_cmd[@]}"; then
    echo "Old display managers and desktop environments removed successfully."
    echo
    echo "NOTE: Your current graphical session is still running.  The old DM has"
    echo "been disabled and will not start on next boot.  Reboot after the script"
    echo "finishes to switch to Ly + dwm."
  else
    echo "Warning: Some packages could not be removed. You may need to handle them manually." >&2
  fi
  echo
}

# ly_write_animation ANIM — back up /etc/ly/config.ini and set its
# `animation =` line to ANIM. Shared by the interactive prompt in
# configure_ly_display_manager and the non-interactive (ACCEPT_DEFAULTS=1)
# branch that applies the TUI-chosen SELECTIONS[ly/animation] during
# Preview & Apply.
ly_write_animation() {
  local ly_config="/etc/ly/config.ini"
  local chosen_animation="$1"

  # Back up the config before making changes
  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  run_with_privilege cp "$ly_config" "${ly_config}.${timestamp}.bak"
  echo "Config backed up to ${ly_config}.${timestamp}.bak"

  # Update animation setting
  echo "Updating animation to: ${chosen_animation}"
  require_command python3 "Python 3 is needed to update Ly animation configuration."
  run_with_privilege python3 - "$ly_config" "$chosen_animation" <<'PY'
import sys
import re

path, animation = sys.argv[1:3]
with open(path, 'r') as fh:
    lines = fh.readlines()

# Update or add animation setting
updated_lines = []
animation_found = False

for line in lines:
    # Match animation=value or animation = value (with any amount of whitespace)
    if re.match(r'^\s*animation\s*=\s*', line):
        updated_lines.append(f'animation = {animation}\n')
        animation_found = True
    else:
        updated_lines.append(line)

# If animation setting wasn't found, add it
if not animation_found:
    updated_lines.append(f'animation = {animation}\n')

with open(path, 'w') as fh:
    fh.writelines(updated_lines)
PY
}

configure_ly_display_manager() {
  # Check if Ly is installed via pacman
  if ! command -v pacman >/dev/null 2>&1 || ! pacman -Qi ly >/dev/null 2>&1; then
    echo "Ly display manager not installed, skipping configuration."
    echo "Install Ly with: sudo pacman -S ly"
    return
  fi

  echo
  echo "Configuring Ly display manager for dwm..."

  local ly_config="/etc/ly/config.ini"

  # Newer ly packages ship a templated ly@.service (one instance per TTY)
  # instead of a plain ly.service; enable whichever this system provides.
  local ly_unit="ly.service"
  if [ ! -f /usr/lib/systemd/system/ly.service ]; then
    local ly_tty=""
    if run_with_privilege test -f "$ly_config"; then
      ly_tty=$(run_with_privilege grep -E '^[[:space:]]*tty[[:space:]]*=' "$ly_config" 2>/dev/null | head -n1 | sed 's/.*=[[:space:]]*//' | tr -d '[:space:]' || true)
    fi
    ly_unit="ly@tty${ly_tty:-2}.service"
  fi

  # I-C2: when selection state is available (state.sh sourced — always true
  # from manjaro-sl.sh, never true from the legacy build_suckless.sh path)
  # and ly/enable was EXPLICITLY set to "off" (e.g. via appearance_menu's
  # "Enable Ly on boot" radiolist), skip enabling/starting Ly entirely —
  # it's write-only otherwise: a user who unchecks "Enable Ly on boot" still
  # got it enabled and started. Unset
  # (state function absent, or key never set) keeps today's behavior: enable
  # + start as before. state_get itself can't distinguish "unset" from
  # "explicitly off" (both fall back to "off"), so the SELECTIONS array is
  # checked directly here rather than via state_get. The animation-write
  # path below is unaffected either way, so a chosen animation still lands
  # in /etc/ly/config.ini.
  local ly_enable_off=0
  if declare -F state_get >/dev/null 2>&1 \
    && [ -n "${SELECTIONS[ly/enable]+x}" ] && [ "${SELECTIONS[ly/enable]}" = "off" ]; then
    ly_enable_off=1
  fi

  if [ "$ly_enable_off" -eq 1 ]; then
    echo "Note: ly/enable is off — skipping Ly service enable/start (animation settings, if any, are still applied below)."
  else
    # Enable Ly service
    echo "Enabling Ly service (${ly_unit})..."
    if run_with_privilege systemctl enable "$ly_unit"; then
      echo "Ly service enabled successfully."
    else
      echo "Warning: Failed to enable Ly service, but continuing..."
    fi

    # Two enabled display managers race for the seat on boot, which is the
    # classic black-screen scenario, so disable any others that are enabled.
    for dm in "${KNOWN_DISPLAY_MANAGERS[@]}"; do
      if systemctl is-enabled "${dm}.service" >/dev/null 2>&1; then
        echo "Disabling ${dm} so it does not conflict with Ly on next boot..."
        run_with_privilege systemctl disable "${dm}.service" || true
      fi
    done
  fi

  # Configure Ly animation
  if run_with_privilege test -f "$ly_config"; then
    # Configure Ly animation
    if [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
      echo "Found Ly config file, configuring animation..."
      echo
      echo "Choose Ly animation style:"
      echo "1) Default (none)"
      echo "2) Doom"
      echo "3) Matrix"
      echo "4) ColorMix"
      echo "5) Keep current"
      echo

      local current_animation
      current_animation=$(run_with_privilege grep -E '^\s*animation\s*=' "$ly_config" 2>/dev/null | sed 's/^\s*animation\s*=\s*//' | tr -d ' ' || echo "none")
      echo "Current animation: ${current_animation}"

      local chosen_animation
      while true; do
        read -r -p "Enter your choice (1-5): " choice || choice=""
        case "$choice" in
          1) chosen_animation="none"; break ;;
          2) chosen_animation="doom"; break ;;
          3) chosen_animation="matrix"; break ;;
          4) chosen_animation="colormix"; break ;;
          5) chosen_animation="$current_animation"; break ;;
          *)
            if [ -n "$choice" ]; then
              echo "Invalid choice. Please enter a number between 1-5." >&2
            else
              echo "No choice entered, keeping current: ${current_animation}" >&2
              chosen_animation="$current_animation"
              break
            fi
            ;;
        esac
      done

      # Sync dwm's wallpaper animation to the chosen Ly animation when the
      # user opted in. state.sh/wallpaper.sh aren't sourced on the legacy
      # build_suckless.sh path, so these calls must stay no-ops there.
      # This bare state_set (not select_wallpaper) is deliberate: this
      # interactive branch is unreachable from apply_all (which forces
      # ACCEPT_DEFAULTS=1) and runs inside a run_step subshell after the
      # Build step, so flipping component/* here could never build anything.
      if declare -F state_on >/dev/null 2>&1 && declare -F state_set >/dev/null 2>&1 \
        && declare -F ly_animation_to_wallpaper >/dev/null 2>&1 \
        && state_on ly/match_wallpaper; then
        local mapped_wallpaper
        mapped_wallpaper=$(ly_animation_to_wallpaper "$chosen_animation")
        state_set dwm/wallpaper "$mapped_wallpaper"
        if [ "$mapped_wallpaper" = "none" ] && [ "$chosen_animation" != "none" ] \
          && declare -F tui_msgbox >/dev/null 2>&1; then
          tui_msgbox "Wallpaper" "The '${chosen_animation}' Ly animation does not have a matching dwm wallpaper yet — that arrives in phase 3. Falling back to no wallpaper animation for dwm."
        fi
      fi

      ly_write_animation "$chosen_animation"
      echo "Updated Ly animation to '${chosen_animation}'."
    elif [ "$ACCEPT_DEFAULTS" -eq 1 ] && declare -F state_get >/dev/null 2>&1; then
      # Non-interactive (Preview & Apply / apply_all) path: the animation the
      # user picked in the TUI's appearance_menu lives in SELECTIONS[ly/animation],
      # but the interactive prompt above never runs under ACCEPT_DEFAULTS=1,
      # so without this branch the TUI-chosen animation was silently dropped.
      local noninteractive_animation
      noninteractive_animation=$(state_get ly/animation)
      if [ -n "$noninteractive_animation" ] && [ "$noninteractive_animation" != "off" ]; then
        ly_write_animation "$noninteractive_animation"
        echo "Updated Ly animation to '${noninteractive_animation}'."
      fi
    fi
  else
    echo "Warning: Ly config file not found at $ly_config"
  fi

  # Starting Ly from inside a running desktop can steal the VT and leave the
  # current session on a black screen, so only start it when no graphical
  # session is active.
  if [ "$ly_enable_off" -eq 1 ]; then
    : # already noted above; ly/enable=off means don't start Ly either
  elif [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    echo "Graphical session detected; not starting Ly now."
    echo "Ly is enabled and will take over after a reboot."
  else
    echo "Starting Ly service (${ly_unit})..."
    if run_with_privilege systemctl start "$ly_unit"; then
      echo "Ly service started successfully."
    else
      echo "Warning: Failed to start Ly service, but continuing..."
    fi
  fi

  echo
  echo "Ly display manager configuration complete."
  echo "You can now reboot to use the graphical login with dwm."
}
