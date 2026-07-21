#!/usr/bin/env bash
# Recommended/build package lists and pacman installation helpers.

# Route mutating privileged commands through run_mut (dry-run aware) when
# it's available (manjaro-sl.sh sources lib/exec.sh); build_suckless.sh
# doesn't define DRY_RUN/run_mut at all, so fall back to run_with_privilege
# directly there — preserves that entry point's existing behavior exactly.
_priv() {
  if declare -F run_mut >/dev/null 2>&1; then
    run_mut sudo: "$@"
  else
    run_with_privilege "$@"
  fi
}

RECOMMENDED_PACKAGES=(
  feh
  ly
  xorg
  xorg-xinit
  meson
  fastfetch
  htop
  nano
  networkmanager
  network-manager-applet
  tldr
  brightnessctl
  alsa-utils
  firefox
  net-tools
)

# Toolchain and libraries needed to compile dwm/dmenu/st/slstatus, plus
# python which this script uses for config edits.
BUILD_PACKAGES=(
  base-devel
  libx11
  libxft
  libxinerama
  freetype2
  fontconfig
  pkgconf
  python
)

# Enable (and start) NetworkManager so networking works out of the box and
# the nm-applet tray icon in the dwm systray has a service to talk to. The
# old "System Tweaks" section used to do this; folded into the install path
# now that that section is gone. Routed through run_mut so --dry-run only
# prints. A no-op with a warning when pacman/networkmanager isn't present.
ensure_networkmanager_enabled() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "Warning: systemctl not found; skipping NetworkManager enable." >&2
    return
  fi
  # Under --dry-run just print the command (nothing was really installed, so
  # probing the live unit would give a misleading preview). On a real run,
  # skip gracefully when the unit is absent — e.g. the minimal preset doesn't
  # install networkmanager — rather than hard-failing the whole apply.
  if [ "${DRY_RUN:-0}" -eq 0 ] \
    && ! systemctl list-unit-files NetworkManager.service --no-legend 2>/dev/null | grep -q .; then
    echo "Warning: NetworkManager.service not found (is networkmanager installed?); skipping enable." >&2
    return
  fi
  echo "Enabling NetworkManager.service (needed for networking + nm-applet)."
  run_mut sudo: systemctl enable --now NetworkManager.service
}

ensure_multilib_repo_enabled() {
  local pacman_conf="/etc/pacman.conf"

  if [ ! -f "$pacman_conf" ]; then
    echo "Warning: $pacman_conf not found; skipping multilib repository configuration." >&2
    return
  fi

  if grep -Eq '^[[:space:]]*\[multilib\][[:space:]]*$' "$pacman_conf"; then
    if awk '/^[[:space:]]*\[multilib\][[:space:]]*$/{flag=1;next} /^[[:space:]]*\[/{flag=0} flag && $0 ~ /^[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist/{found=1} END{exit !found}' "$pacman_conf"; then
      echo "pacman multilib repository already enabled."
      return
    fi
  fi

  if ! grep -Eq '^[[:space:]]*#\s*\[multilib\]' "$pacman_conf"; then
    echo "Warning: unable to find a commented multilib section in $pacman_conf; please enable it manually if needed." >&2
    return
  fi

  require_command python3 "Python 3 is needed to update $pacman_conf."

  echo "Enabling pacman multilib repository in $pacman_conf."
  if _priv python3 - "$pacman_conf" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    lines = fh.readlines()

changed = False
for idx, line in enumerate(lines):
    stripped = line.lstrip()
    bare = stripped.lstrip('#').strip()
    if bare.lower() == '[multilib]':
        prefix = line[: len(line) - len(stripped)]
        desired = f"{prefix}[multilib]\n"
        if line != desired:
            lines[idx] = desired
            changed = True

        j = idx + 1
        while j < len(lines):
            next_line = lines[j]
            next_stripped = next_line.strip()
            if not next_stripped:
                j += 1
                continue
            if next_stripped.startswith('['):
                break
            bare_next = next_line.lstrip().lstrip('#').strip()
            if bare_next.lower().startswith('include'):
                prefix_next = next_line[: len(next_line) - len(next_line.lstrip())]
                desired_next = f"{prefix_next}{bare_next}\n"
                if next_line != desired_next:
                    lines[j] = desired_next
                    changed = True
                break
            j += 1
        break

if changed:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.writelines(lines)
PY
  then
    if grep -Eq '^[[:space:]]*\[multilib\][[:space:]]*$' "$pacman_conf" && \
       awk '/^[[:space:]]*\[multilib\][[:space:]]*$/{flag=1;next} /^[[:space:]]*\[/{flag=0} flag && $0 ~ /^[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist/{found=1} END{exit !found}' "$pacman_conf"; then
      echo "Enabled pacman multilib repository."
    else
      echo "Warning: attempted to enable multilib but validation failed; please verify $pacman_conf manually." >&2
    fi
  else
    echo "Warning: failed to update $pacman_conf; please enable multilib manually." >&2
  fi
}

ensure_recommended_packages() {
  if [ "$CHECK_PACKAGES" -eq 0 ]; then
    echo "Skipping recommended package installation check."
    return
  fi

  if ! command -v pacman >/dev/null 2>&1; then
    echo "Warning: pacman not found; this script targets Arch-based distros. Skipping package installation." >&2
    return
  fi

  ensure_multilib_repo_enabled

  local wanted_packages=("${RECOMMENDED_PACKAGES[@]}" "${BUILD_PACKAGES[@]}")
  local missing_packages=()
  for package in "${wanted_packages[@]}"; do
    # Check if it's a package group (like xorg) or individual package
    if pacman -Sg "$package" >/dev/null 2>&1; then
      # It's a package group, check if any packages from the group are installed
      local group_installed=false
      while read -r group_package; do
        if pacman -Qi "$group_package" >/dev/null 2>&1; then
          group_installed=true
          break
        fi
      done < <(pacman -Sg "$package" | awk '{print $2}')

      if [ "$group_installed" = false ]; then
        missing_packages+=("$package")
      fi
    else
      # It's an individual package
      if ! pacman -Qi "$package" >/dev/null 2>&1; then
        missing_packages+=("$package")
      fi
    fi
  done

  if [ ${#missing_packages[@]} -eq 0 ]; then
    echo "All recommended packages are already installed."
    return
  fi

  echo "Recommended packages not found: ${missing_packages[*]}"

  local should_install="yes"
  if [ "$ACCEPT_DEFAULTS" -eq 0 ]; then
    if prompt_yes_no "Install recommended packages with pacman?" "y"; then
      should_install="yes"
    else
      should_install="no"
    fi
  fi

  if [ "$should_install" = "yes" ]; then
    local pacman_cmd=(pacman -Syu --needed)
    if [ "$ACCEPT_DEFAULTS" -eq 1 ]; then
      pacman_cmd+=(--noconfirm)
    fi
    pacman_cmd+=("${missing_packages[@]}")
    echo "Installing recommended packages: ${missing_packages[*]}"
    _priv "${pacman_cmd[@]}"
    echo "Recommended packages installation complete."
  else
    echo "Skipping installation of recommended packages."
  fi
}
