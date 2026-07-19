#!/usr/bin/env bash
# Build helper for patched suckless utilities.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

DEFAULT_COMPONENTS=(dwm dmenu st slstatus)

ACCEPT_DEFAULTS=0
SLSTATUS_INTERFACE=""
BATTERY_CHOICE=""
BAR_COLOR=""
MODKEY_CHOICE=""
COPY_XINIT=""
COPY_DESKTOP=""
REMOVE_OLD_DE=""
CHECK_PACKAGES=1

usage() {
  cat <<'EOF'
Usage: ./build_suckless.sh [options] [component...]

Build patched suckless components and optionally configure them beforehand.
This script targets Arch-based distributions (pacman), e.g. Arch and Manjaro.

Options:
  -h, --help              Show this help message and exit
  -y, --accept-defaults   Skip interactive prompts and keep current settings
      --interface IFACE   Set network interface for slstatus netspeed widgets
      --battery           Enable the battery widget in slstatus
      --no-battery        Disable the battery widget in slstatus
      --bar-color COLOR   Hex color to use for the dwm selected bar background
      --modkey KEY        Set dwm modkey: 'super' or 'alt' (default: alt)
      --copy-xinit        Copy misc0/xinitrc-config.txt to ~/.xinitrc
      --no-copy-xinit     Skip copying the xinitrc helper (useful with -y)
      --copy-desktop      Copy misc0/dwm.desktop to /usr/share/xsessions/
      --no-copy-desktop   Skip copying the desktop file (useful with -y)
      --remove-de         Remove detected old display managers and desktop environments
      --no-remove-de      Skip removing old display managers and desktop environments
      --skip-packages     Skip the recommended/build package installation step

Components default to: dwm dmenu st slstatus
EOF
}

COMPONENT_ARGS=()

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -y|--accept-defaults)
      ACCEPT_DEFAULTS=1
      ;;
    --interface)
      if [ $# -lt 2 ]; then
        echo "Error: --interface requires a value." >&2
        exit 1
      fi
      SLSTATUS_INTERFACE="$2"
      shift
      ;;
    --battery)
      BATTERY_CHOICE="enable"
      ;;
    --no-battery)
      BATTERY_CHOICE="disable"
      ;;
    --bar-color)
      if [ $# -lt 2 ]; then
        echo "Error: --bar-color requires a value." >&2
        exit 1
      fi
      BAR_COLOR="$2"
      shift
      ;;
    --modkey)
      if [ $# -lt 2 ]; then
        echo "Error: --modkey requires a value (super or alt)." >&2
        exit 1
      fi
      case "$2" in
        super|alt)
          MODKEY_CHOICE="$2"
          ;;
        *)
          echo "Error: --modkey must be 'super' or 'alt'." >&2
          exit 1
          ;;
      esac
      shift
      ;;
    --copy-xinit)
      COPY_XINIT="yes"
      ;;
    --no-copy-xinit)
      COPY_XINIT="no"
      ;;
    --copy-desktop)
      COPY_DESKTOP="yes"
      ;;
    --no-copy-desktop)
      COPY_DESKTOP="no"
      ;;
    --remove-de)
      REMOVE_OLD_DE="yes"
      ;;
    --no-remove-de)
      REMOVE_OLD_DE="no"
      ;;
    --skip-packages)
      CHECK_PACKAGES=0
      ;;
    --)
      shift
      while (($#)); do
        COMPONENT_ARGS+=("$1")
        shift
      done
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      COMPONENT_ARGS+=("$1")
      ;;
  esac
  shift
done

if [ ${#COMPONENT_ARGS[@]} -gt 0 ]; then
  COMPONENTS=("${COMPONENT_ARGS[@]}")
else
  COMPONENTS=("${DEFAULT_COMPONENTS[@]}")
fi

for m in common packages suckless configure ly; do
  source "$REPO_ROOT/lib/$m.sh"
done

detect_and_remove_old_de

ensure_recommended_packages

if component_selected "slstatus"; then
  configure_slstatus_interface
  configure_slstatus_battery "$BATTERY_CHOICE"
fi

if component_selected "dwm"; then
  configure_dwm_bar_color
  configure_dwm_modkey
fi

setup_misc_files

clean_build_artifacts

build_components

# Configure Ly display manager after all components are built (if dwm was built)
if component_selected "dwm"; then
  echo
  configure_ly_display_manager
fi
