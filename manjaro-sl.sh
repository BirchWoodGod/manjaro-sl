#!/usr/bin/env bash
# manjaro-sl — Manjaro debloater + DWM/suckless setup TUI.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Side-effect-free modules only, sourced before argument parsing: exec/tui/
# state just define functions and arrays. lib/common.sh (sourced further
# below) runs top-level code that `exit 1`s when sudo is missing, which
# broke `--help` on fresh installs in an earlier task — so -h/--help must be
# handled before common.sh (and everything that depends on it) is sourced.
for m in exec tui state; do
  source "$REPO_ROOT/lib/$m.sh"
done

usage() {
  cat <<'EOF'
Usage: ./manjaro-sl.sh [options]

Interactive whiptail TUI for debloating Manjaro and installing dwm/suckless
tools (dwm, dmenu, st, slstatus, doomfire) with a Ly display manager.

Options:
  -h, --help    Show this help message and exit

Full non-interactive flag parsing (--preset, --only, --dry-run, --profile,
--enable-<slug>/--disable-<slug>, ...) arrives in a later step; for now any
other arguments are accepted and fall back to non-interactive scaffold mode.
EOF
}

# Minimal arg parsing for this step: only recognize -h/--help (so it can
# exit before lib/common.sh's sudo check runs); everything else is left
# untouched in "$@" for main() below. A full parser lands later.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

for m in common packages suckless configure ly debloat tweaks wallpaper; do
  source "$REPO_ROOT/lib/$m.sh"
done

# Legacy globals consumed by the modules sourced above (configure_*,
# ensure_recommended_packages, detect_and_remove_old_de, ...). Defaults
# mirror build_suckless.sh so those functions behave the same when driven
# from here.
ACCEPT_DEFAULTS=${ACCEPT_DEFAULTS:-0}
SLSTATUS_INTERFACE=${SLSTATUS_INTERFACE:-}
BATTERY_CHOICE=${BATTERY_CHOICE:-}
BAR_COLOR=${BAR_COLOR:-}
MODKEY_CHOICE=${MODKEY_CHOICE:-}
COPY_XINIT=${COPY_XINIT:-}
COPY_DESKTOP=${COPY_DESKTOP:-}
REMOVE_OLD_DE=${REMOVE_OLD_DE:-}
CHECK_PACKAGES=${CHECK_PACKAGES:-1}
declare -ga COMPONENTS=()

sanity_checks() {
  command -v pacman >/dev/null || { echo "pacman not found — Arch-based distro required." >&2; exit 1; }
  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    echo "Warning: run as your normal user; sudo is used only where needed." >&2
  fi
  if ! tui_available && [ "$TUI_ACTIVE" -eq 1 ]; then
    if tui_yesno "whiptail missing" "Install libnewt (whiptail) for the menu UI?"; then
      run_mut sudo: pacman -S --needed --noconfirm libnewt
    else
      TUI_ACTIVE=0
    fi
  fi
}

# Checklist of components from DEFAULT_COMPONENTS (dwm dmenu st slstatus)
# plus doomfire → SELECTIONS[component/*].
install_screen() {
  local -a comps=(dwm dmenu st slstatus doomfire)
  local -A descs=(
    [dwm]="Window manager"
    [dmenu]="Program launcher"
    [st]="Terminal emulator"
    [slstatus]="Status bar"
    [doomfire]="DOOM fire X11 wallpaper animation"
  )
  local -a args=()
  local c state
  for c in "${comps[@]}"; do
    state=$(state_get "component/$c")
    args+=("$c" "${descs[$c]}" "$state")
  done
  local chosen
  chosen=$(tui_checklist "Install DWM & suckless tools" "Space toggles, Enter confirms" "${args[@]}") || return 0
  for c in "${comps[@]}"; do state_set "component/$c" off; done
  local tag; for tag in $chosen; do state_set "component/$tag" on; done
}

# Loops a tui_menu over the four debloat categories + old DE/DM removal.
debloat_menu() {
  while true; do
    local pick
    pick=$(tui_menu "Debloat Manjaro" "Category" \
      manjaro "Manjaro-branded packages" apps "Pre-installed apps" \
      printing "Printer/scanner stack" bluetooth "Bluetooth stack" \
      dedm "Old desktop environments / display managers" back "Back") || return 0
    case "$pick" in
      manjaro)   debloat_screen "Manjaro packages" "$REPO_ROOT/data/debloat-manjaro.list" ;;
      apps)      debloat_screen "Pre-installed apps" "$REPO_ROOT/data/debloat-apps.list" ;;
      printing)  debloat_screen "Printing stack" "$REPO_ROOT/data/debloat-printing.list" ;;
      bluetooth) debloat_screen "Bluetooth stack" "$REPO_ROOT/data/debloat-bluetooth.list" ;;
      dedm)      debloat_screen "Old DEs" "$REPO_ROOT/data/de.list"
                 debloat_screen "Old DMs" "$REPO_ROOT/data/dm.list" ;;
      back|"")   return 0 ;;
    esac
  done
}

# Loops a tui_menu over dwm settings; each leaf is one tui_radiolist/
# tui_checklist/tui_input call storing into SELECTIONS. "off" is used as the
# sentinel for "keep current / auto-detect" (see apply_configuration).
dwm_menu() {
  while true; do
    local pick
    pick=$(tui_menu "Configure DWM" "Setting" \
      modkey "Modkey (super/alt)" barcolor "Selected bar accent color" \
      wallpaper "Wallpaper animation" battery "slstatus battery widget" \
      interface "slstatus network interface" back "Back") || return 0
    case "$pick" in
      modkey)
        local cur sel
        cur=$(state_get dwm/modkey)
        sel=$(tui_radiolist "Modkey" "Choose dwm modkey" \
          off   "Keep current (auto-detected)" "$([ "$cur" = off ] && echo on || echo off)" \
          super "Super (Windows/Command key)"  "$([ "$cur" = super ] && echo on || echo off)" \
          alt   "Alt"                          "$([ "$cur" = alt ] && echo on || echo off)") || continue
        state_set dwm/modkey "$sel"
        ;;
      barcolor)
        local cur sel
        cur=$(state_get dwm/barcolor); [ "$cur" = off ] && cur=""
        sel=$(tui_input "Bar color" "Hex color for the dwm selected bar (e.g. #268bd2); blank = keep current" "$cur") || continue
        if [ -n "$sel" ]; then state_set dwm/barcolor "$sel"; else state_set dwm/barcolor off; fi
        ;;
      wallpaper)
        local cur sel
        cur=$(state_get dwm/wallpaper); [ "$cur" = off ] && cur=none
        sel=$(tui_radiolist "Wallpaper" "Choose dwm wallpaper animation" \
          none     "None"     "$([ "$cur" = none ] && echo on || echo off)" \
          doomfire "DOOM fire" "$([ "$cur" = doomfire ] && echo on || echo off)") || continue
        state_set dwm/wallpaper "$sel"
        ;;
      battery)
        local cur chosen
        cur=$(state_get dwm/battery)
        chosen=$(tui_checklist "Battery widget" "Space toggles, Enter confirms" battery "Enable slstatus battery widget" "$cur") || continue
        if [ -n "$chosen" ]; then state_set dwm/battery on; else state_set dwm/battery off; fi
        ;;
      interface)
        local cur sel
        cur=$(state_get dwm/interface); [ "$cur" = off ] && cur=""
        sel=$(tui_input "Network interface" "slstatus netspeed interface; blank = auto-detect" "$cur") || continue
        if [ -n "$sel" ]; then state_set dwm/interface "$sel"; else state_set dwm/interface off; fi
        ;;
      back|"") return 0 ;;
    esac
  done
}

# Loops a tui_menu over Ly settings: enable on boot, animation, and whether
# the animation should be mirrored to the dwm wallpaper.
ly_menu() {
  while true; do
    local pick
    pick=$(tui_menu "Ly Display Manager" "Setting" \
      enable "Enable Ly on boot" animation "Login animation" \
      match "Sync animation to dwm wallpaper" back "Back") || return 0
    case "$pick" in
      enable)
        local cur chosen
        cur=$(state_get ly/enable)
        chosen=$(tui_checklist "Ly" "Space toggles, Enter confirms" enable "Enable and start Ly on next boot" "$cur") || continue
        if [ -n "$chosen" ]; then state_set ly/enable on; else state_set ly/enable off; fi
        ;;
      animation)
        local cur sel
        cur=$(state_get ly/animation); [ "$cur" = off ] && cur=none
        sel=$(tui_radiolist "Ly animation" "Choose login animation" \
          none     "None"     "$([ "$cur" = none ] && echo on || echo off)" \
          doom     "Doom"     "$([ "$cur" = doom ] && echo on || echo off)" \
          matrix   "Matrix"   "$([ "$cur" = matrix ] && echo on || echo off)" \
          colormix "ColorMix" "$([ "$cur" = colormix ] && echo on || echo off)") || continue
        state_set ly/animation "$sel"
        ;;
      match)
        local cur chosen
        cur=$(state_get ly/match_wallpaper)
        chosen=$(tui_checklist "Ly" "Space toggles, Enter confirms" match_wallpaper "Sync dwm wallpaper to Ly animation" "$cur") || continue
        if [ -n "$chosen" ]; then state_set ly/match_wallpaper on; else state_set ly/match_wallpaper off; fi
        ;;
      back|"") return 0 ;;
    esac
  done
}

# reconfigure_load is Task 10's job (reads live system state into
# SELECTIONS); stubbed here so the "Reconfigure" menu entry has somewhere
# to go without erroring.
reconfigure_load() {
  tui_msgbox "Reconfigure" "Coming in the next step."
}

# Renders the current SELECTIONS grouped into the sections the design spec's
# Preview screen calls for: REMOVE / INSTALL / BUILD / CONFIGURE / TWEAKS /
# WALLPAPER. Plain text; "(none)" for empty groups.
preview_text() {
  local out="" list key

  # NOTE: debloat_collect's own return status reflects whatever its last
  # loop iteration's test evaluated to (not necessarily 0), so it must be
  # consumed via process substitution rather than `$(debloat_collect | ...)`
  # — under `set -euo pipefail` the latter trips -e on the assignment even
  # though every package name was collected correctly.
  list=""
  local pkg
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && list+="$pkg "
  done < <(debloat_collect)
  list=${list% }
  out+="REMOVE:\n  ${list:-(none)}\n\n"

  list=""
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == install/* ]] && [ "${SELECTIONS[$key]}" = on ] && list+="${key#install/} "
  done
  list=${list% }
  out+="INSTALL:\n  ${list:-(none)}\n\n"

  list=""
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == component/* ]] && [ "${SELECTIONS[$key]}" = on ] && list+="${key#component/} "
  done
  list=${list% }
  out+="BUILD:\n  ${list:-(none)}\n\n"

  # CONFIGURE covers dwm/* settings other than wallpaper, which gets its own
  # section below (it's applied by wallpaper_apply, not apply_configuration).
  list=""
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == dwm/* ]] || continue
    [ "$key" = "dwm/wallpaper" ] && continue
    [ "${SELECTIONS[$key]}" = "off" ] && continue
    list+="${key#dwm/}=${SELECTIONS[$key]} "
  done
  list=${list% }
  out+="CONFIGURE:\n  ${list:-(none)}\n\n"

  list=""
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == tweak/* ]] && [ "${SELECTIONS[$key]}" = on ] && list+="${key#tweak/} "
  done
  list=${list% }
  out+="TWEAKS:\n  ${list:-(none)}\n\n"

  local wp; wp=$(state_get dwm/wallpaper)
  [ "$wp" = "off" ] && wp="none"
  [ "$wp" = "none" ] && wp="(none)"
  out+="WALLPAPER:\n  ${wp}"

  printf '%b' "$out"
}

# Thin adapter: wanted = data/install-core.list (always) + SELECTIONS[install/*]=on
# (the recommended list, toggled by presets). Reuses ensure_recommended_packages
# (and its run_with_privilege-based pacman calls) rather than reimplementing
# the missing-package check, by temporarily overriding the package arrays it
# reads its lists from.
install_selected_packages() {
  local -a core_names=() rec_selected=()
  local name desc state key
  while IFS='|' read -r name desc state; do core_names+=("$name"); done \
    < <(list_entries "$REPO_ROOT/data/install-core.list")
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == install/* ]] && [ "${SELECTIONS[$key]}" = on ] && rec_selected+=("${key#install/}")
  done

  local -a saved_recommended=("${RECOMMENDED_PACKAGES[@]}")
  local -a saved_build=("${BUILD_PACKAGES[@]}")
  RECOMMENDED_PACKAGES=("${rec_selected[@]}")
  BUILD_PACKAGES=("${core_names[@]}")
  ensure_recommended_packages
  RECOMMENDED_PACKAGES=("${saved_recommended[@]}")
  BUILD_PACKAGES=("${saved_build[@]}")
}

# Thin adapter: COMPONENTS = SELECTIONS[component/*]=on, then reuse
# clean_build_artifacts + build_components.
build_selected_components() {
  COMPONENTS=()
  local key
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == component/* ]] && [ "${SELECTIONS[$key]}" = on ] && COMPONENTS+=("${key#component/}")
  done
  if [ ${#COMPONENTS[@]} -eq 0 ]; then
    echo "No components selected for building."
    return 0
  fi
  clean_build_artifacts
  build_components
}

# Thin adapter: maps SELECTIONS onto the legacy configure_* globals. Reads
# state via state_get/state_on directly (not the COMPONENTS array set by
# build_selected_components) because run_step pipes each step's function
# through `tee`, and every command in a bash pipeline — including the first
# stage — runs in a subshell, so a global array assigned in one run_step
# call would not survive into the next one.
apply_configuration() {
  MODKEY_CHOICE=$(state_get dwm/modkey); [ "$MODKEY_CHOICE" = off ] && MODKEY_CHOICE=""
  BAR_COLOR=$(state_get dwm/barcolor); [ "$BAR_COLOR" = off ] && BAR_COLOR=""
  SLSTATUS_INTERFACE=$(state_get dwm/interface); [ "$SLSTATUS_INTERFACE" = off ] && SLSTATUS_INTERFACE=""
  BATTERY_CHOICE=""
  state_on dwm/battery && BATTERY_CHOICE="enable"
  COPY_XINIT=${COPY_XINIT:-yes}
  COPY_DESKTOP=${COPY_DESKTOP:-yes}
  ACCEPT_DEFAULTS=1

  if state_on "component/slstatus"; then
    configure_slstatus_interface
    configure_slstatus_battery "$BATTERY_CHOICE"
  fi
  if state_on "component/dwm"; then
    configure_dwm_bar_color
    configure_dwm_modkey
  fi
  setup_misc_files
}

# Fixed order: debloat → tweaks → install → build → configure → ly →
# wallpaper → summary, each via run_step so failures offer continue/abort.
apply_all() {
  ACCEPT_DEFAULTS=1
  run_step "Debloat"           debloat_apply
  run_step "System tweaks"     tweaks_apply
  run_step "Install packages"  install_selected_packages
  run_step "Build components"  build_selected_components
  run_step "Configure"         apply_configuration
  run_step "Ly"                configure_ly_display_manager
  run_step "Wallpaper"         wallpaper_apply
  profile_save "$HOME/.config/manjaro-sl/profile"
  tui_msgbox "Done" "All steps finished. Log: ${RUN_LOG:-none}\nReboot to switch to Ly + dwm."
}

main_menu() {
  while true; do
    local pick
    pick=$(tui_menu "manjaro-sl" "Main menu" \
      reconfig "Reconfigure existing setup" install "Install DWM & suckless tools" \
      debloat "Debloat Manjaro" dwm "Configure DWM" tweaks "System tweaks" \
      ly "Ly display manager" preset "Apply preset" apply "Preview & apply" quit "Quit") || pick=quit
    case "$pick" in
      reconfig) reconfigure_load ;;
      install)  install_screen ;;
      debloat)  debloat_menu ;;
      dwm)      dwm_menu ;;
      tweaks)   tweaks_screen ;;
      ly)       ly_menu ;;
      preset)   local p; p=$(tui_radiolist "Preset" "Choose" recommended "Recommended" on minimal "Minimal" off) && preset_apply "$p" ;;
      apply)    if tui_yesno "Preview" "$(preview_text)\n\nApply now?"; then apply_all; fi ;;
      quit|"")  break ;;
    esac
  done
}

main() {
  if [ "$#" -eq 0 ]; then
    sanity_checks
    main_menu
  else
    # Full flag parsing arrives in Task 10; for now don't try to guess what
    # unrecognized arguments mean, and don't launch the interactive menu
    # when the caller passed arguments intended for a non-interactive run.
    echo "manjaro-sl: scaffold (non-interactive flag parsing arrives in a later step)"
  fi
}

# Guard so sourcing this file (tests, `bash -c 'source manjaro-sl.sh'` syntax
# checks) only defines the functions above without launching the TUI.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
