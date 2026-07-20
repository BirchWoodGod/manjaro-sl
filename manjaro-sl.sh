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
Usage: ./manjaro-sl.sh [options] [component...]

With no options, launches the interactive whiptail TUI for debloating
Manjaro and installing dwm/suckless tools (dwm, dmenu, st, slstatus,
doomfire, xmatrix, xcolormix, xgameoflife, xblackhole, xstarfield, xplasma, xrain, xfireflies) with a Ly
display manager.

With any options, flags are processed left-to-right and build up the same
selection state the TUI edits; pass --apply (or -y) to apply it
non-interactively instead of opening the menu. Because flags apply in
order, --preset NAME bulk-sets selections at the point it's parsed, so
any --enable-*/--disable-* (or other) flags placed AFTER it on the command
line override what the preset chose; flags placed before a --preset get
overridden by it instead. Bare component names (dwm, dmenu, st, slstatus,
or any built wallpaper — legacy build_suckless.sh muscle memory, e.g. `./manjaro-sl.sh
st`) are applied last, after any --preset, and select only the named
component(s) for building, overriding whatever components the preset chose.

Options:
  -h, --help                Show this help message and exit
  -y, --accept-defaults     Non-interactive; implies --apply unless already
                            given
  --apply                   Skip the TUI and apply the selections built up by
                            the flags so far
  --dry-run                 Print mutating commands instead of running them
  --preset NAME             Bulk-apply a preset: 'recommended' or 'minimal'
  --only SECTION            Restrict --apply to one section (repeatable):
                            install|debloat|tweaks|dwm|ly
  --profile FILE            Load previously saved selections from FILE
  --wallpaper WP            Set dwm wallpaper animation: 'none' or any built
                            wallpaper (doomfire, xmatrix, xcolormix,
                            xgameoflife, xblackhole, xstarfield, xplasma, xrain, xfireflies)
  --enable-SLUG             Turn on a debloat/install entry by package name
  --disable-SLUG            Turn off a debloat/install entry by package name
  --interface IFACE         Set slstatus network interface
  --battery                 Enable the slstatus battery widget
  --no-battery              Disable the slstatus battery widget
  --bar-color COLOR         Hex color for the dwm selected bar
  --modkey KEY              dwm modkey: 'super' or 'alt'
  --remove-de               Mark installed old DEs/DMs for removal
  --no-remove-de            Leave old DEs/DMs alone (default)
  --skip-packages           Skip the recommended/build package install step
  --copy-xinit              Copy the xinitrc helper to ~/.xinitrc
  --no-copy-xinit           Skip copying the xinitrc helper
  --copy-desktop            Copy the dwm.desktop session entry
  --no-copy-desktop         Skip copying the dwm.desktop session entry

Examples:
  ./manjaro-sl.sh --preset minimal --dry-run --apply
  ./manjaro-sl.sh -y
  ./manjaro-sl.sh --interface wlan0 --battery
  ./manjaro-sl.sh --only debloat --dry-run --apply
  ./manjaro-sl.sh --wallpaper doomfire
  ./manjaro-sl.sh --profile ~/.config/manjaro-sl/profile --apply
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

# CLI-flag-driven state (Task 10). ONLY_SECTIONS restricts apply_all to
# matching steps (empty = all); SKIP_PACKAGES/APPLY_NOW/Y_FLAG are simple
# switches set while parsing argv in parse_args (see below).
declare -ga ONLY_SECTIONS=()
SKIP_PACKAGES=0
APPLY_NOW=0
Y_FLAG=0
# Set when -y/--accept-defaults is parsed (see apply_configuration's
# COPY_XINIT/COPY_DESKTOP default — legacy build_suckless.sh -y defaulted
# both to "no", but interactive TUI Preview & Apply should still default to
# "yes"; LEGACY_Y distinguishes the two ACCEPT_DEFAULTS=1 callers).
LEGACY_Y=0

# Bare (non-dash) argv entries collected by parse_args, e.g. `./manjaro-sl.sh
# st` — legacy per-component muscle memory from build_suckless.sh. See
# parse_args' handling below.
declare -ga POSITIONAL_COMPONENTS=()

# Set by detect_existing_setup (Task 4), called unconditionally in main()
# before the interactive main menu (never in the non-interactive --apply
# path). EXISTING_SETUP is 1 when any live-system signal fired; SETUP_BANNER
# is the human-readable banner shown atop the main menu.
EXISTING_SETUP=0
SETUP_BANNER=""

# section_enabled SECTION — true if --only wasn't used at all, or SECTION is
# one of the values it was given. Sections: install|debloat|tweaks|dwm|ly.
section_enabled() {
  local sect="$1" s
  [ ${#ONLY_SECTIONS[@]} -eq 0 ] && return 0
  for s in "${ONLY_SECTIONS[@]}"; do [ "$s" = "$sect" ] && return 0; done
  return 1
}

# N2: old build_suckless.sh only ran Ly configuration when dwm was among the
# selected components — a display manager for a WM you didn't build makes
# little sense, and legacy per-component invocations like `./build_suckless.sh
# st -y` must remain a plain st rebuild, not a side-effecting boot-behavior
# change (ly/enable unset defaults to "enable Ly" — see preview_text's N1
# comment and lib/ly.sh's C2 gate). Restore that gate here: the Ly step in
# apply_all runs only when component/dwm is selected, OR ly/enable was
# EXPLICITLY turned on (opt-in even without rebuilding dwm — e.g. someone
# revisiting just the Ly menu), OR the user explicitly passed `--only ly`.
# That last case composes with section_enabled: section_enabled ly already
# gates out the Ly step entirely unless --only was unused or included "ly",
# so by the time this function runs we know --only ly (if used at all) is
# consistent; here we additionally treat --only ly itself as the opt-in
# signal so asking for exactly the Ly section still reaches the step even
# when dwm isn't selected (otherwise --only ly would silently do nothing on
# a non-dwm run instead of configuring Ly as asked).
ly_step_should_run() {
  state_on "component/dwm" && return 0
  { [ -n "${SELECTIONS[ly/enable]+x}" ] && state_on ly/enable; } && return 0
  local s
  for s in "${ONLY_SECTIONS[@]}"; do [ "$s" = "ly" ] && return 0; done
  return 1
}

sanity_checks() {
  command -v pacman >/dev/null || { echo "pacman not found — Arch-based distro required." >&2; exit 1; }
  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    echo "Warning: run as your normal user; sudo is used only where needed." >&2
  fi
  if ! tui_available && [ "$TUI_ACTIVE" -eq 1 ]; then
    # Non-interactive runs (--apply/-y) must never block on a prompt; just
    # fall back to the plain-text TUI shims instead of offering to install
    # libnewt.
    if [ "$APPLY_NOW" -eq 1 ]; then
      TUI_ACTIVE=0
    elif tui_yesno "whiptail missing" "Install libnewt (whiptail) for the menu UI?"; then
      run_mut sudo: pacman -S --needed --noconfirm libnewt
    else
      TUI_ACTIVE=0
    fi
  fi
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

# Loops a tui_menu over the desktop-side settings: which components get
# built, plus dwm/slstatus configuration knobs. Each leaf is one
# tui_checklist/tui_radiolist/tui_input call storing into SELECTIONS. "off"
# is used as the sentinel for "keep current / auto-detect" (see
# apply_configuration). Wallpaper/animation live in appearance_menu instead —
# this menu is scoped to what apply_configuration + build_selected_components
# consume.
desktop_setup_menu() {
  while true; do
    local pick
    pick=$(tui_menu "Desktop Setup" "Setting" \
      components "Components" modkey "Modkey (super/alt)" \
      barcolor "Selected bar accent color" \
      interface "slstatus network interface" \
      battery "slstatus battery widget" back "Back") || return 0
    case "$pick" in
      components)
        local -a comps=(dwm dmenu st slstatus)
        local -A descs=(
          [dwm]="Window manager"
          [dmenu]="Program launcher"
          [st]="Terminal emulator"
          [slstatus]="Status bar"
        )
        local w
        while IFS= read -r w; do
          comps+=("$w")
          descs[$w]="${WALLPAPER_DESCS[$w]}"
        done < <(available_wallpapers)
        local -a args=()
        local c state
        for c in "${comps[@]}"; do
          state=$(state_get "component/$c")
          args+=("$c" "${descs[$c]}" "$state")
        done
        local chosen
        chosen=$(tui_checklist "Components" "Space toggles, Enter confirms" "${args[@]}") || continue
        for c in "${comps[@]}"; do user_set "component/$c" off; done
        local tag; for tag in $chosen; do user_set "component/$tag" on; done
        ;;
      modkey)
        local cur sel
        cur=$(state_get dwm/modkey)
        sel=$(tui_radiolist "Modkey" "Choose dwm modkey" \
          off   "Keep current (auto-detected)" "$([ "$cur" = off ] && echo on || echo off)" \
          super "Super (Windows/Command key)"  "$([ "$cur" = super ] && echo on || echo off)" \
          alt   "Alt"                          "$([ "$cur" = alt ] && echo on || echo off)") || continue
        user_set dwm/modkey "$sel"
        ;;
      barcolor)
        local cur sel
        cur=$(state_get dwm/barcolor); [ "$cur" = off ] && cur=""
        local shown_cur; shown_cur=$(dwm_current_barcolor)
        local -a c_args=()
        local p name hex matched=0
        for p in "${BAR_PRESETS[@]}"; do
          name=${p%%|*}; hex=${p#*|}
          if [ "$hex" = "$cur" ]; then matched=1; fi
          c_args+=("$hex" "$name — $hex" "$([ "$hex" = "$cur" ] && echo on || echo off)")
        done
        # "Keep current" is the no-change option: pre-select it whenever
        # nothing else is (empty state, or a custom hex no preset matches),
        # so the radiolist always shows a coherent default.
        c_args+=(custom "Custom hex…" off keep "Keep current (${shown_cur:-unknown})" "$([ "$matched" -eq 0 ] && echo on || echo off)")
        sel=$(tui_radiolist "Bar color" "dwm selected-bar background" "${c_args[@]}") || continue
        case "$sel" in
          keep|"") ;;
          custom)
            sel=$(tui_input "Bar color" "Hex color (#RRGGBB)" "$cur") || continue
            if [[ "$sel" =~ ^#[0-9a-fA-F]{6}$ ]]; then
              user_set dwm/barcolor "$sel"
            elif [ -n "$sel" ]; then
              tui_msgbox "Bar color" "'$sel' is not a valid #RRGGBB hex color — keeping the previous setting."
            fi
            ;;
          *) user_set dwm/barcolor "$sel" ;;
        esac
        ;;
      battery)
        local cur chosen
        cur=$(state_get dwm/battery)
        chosen=$(tui_checklist "Battery widget" "Space toggles, Enter confirms" battery "Enable slstatus battery widget" "$cur") || continue
        if [ -n "$chosen" ]; then user_set dwm/battery on; else user_set dwm/battery off; fi
        ;;
      interface)
        local cur sel
        cur=$(state_get dwm/interface); [ "$cur" = off ] && cur=""
        local shown_cur; shown_cur=$(slstatus_current_interface)
        local -a if_args=()
        local iface matched=0
        while IFS= read -r iface; do
          if [ "$iface" = "$cur" ]; then matched=1; fi
          if_args+=("$iface" "detected" "$([ "$iface" = "$cur" ] && echo on || echo off)")
        done < <(detect_net_interfaces)
        if [ ${#if_args[@]} -eq 0 ]; then
          sel=$(tui_input "Network interface" "No interfaces detected; enter one" "$cur") || continue
          [ -n "$sel" ] && user_set dwm/interface "$sel"
          continue
        fi
        # Same coherent-default rule as the bar-color picker: pre-select
        # "keep" when the stored value is empty or not among the detected
        # interfaces (e.g. stale after a hardware change).
        if_args+=(custom "Custom…" off keep "Keep current (${shown_cur:-unknown})" "$([ "$matched" -eq 0 ] && echo on || echo off)")
        sel=$(tui_radiolist "Network interface" "slstatus netspeed interface" "${if_args[@]}") || continue
        case "$sel" in
          keep|"") ;;
          custom)
            sel=$(tui_input "Network interface" "Interface name" "$cur") || continue
            [ -n "$sel" ] && user_set dwm/interface "$sel"
            ;;
          *) user_set dwm/interface "$sel" ;;
        esac
        ;;
      back|"") return 0 ;;
    esac
  done
}

# select_wallpaper WP — the single chokepoint for writing dwm/wallpaper.
# Nothing else couples a chosen wallpaper to the component/* selection that
# actually builds it, so a wallpaper picked here without also flipping on
# its component gets exec'd by wallpaper.sh's launcher without ever having
# been built or installed (I1 — flagship final-review-v2 bug; the launcher
# runs backgrounded from ~/.xinitrc, so the failure is silent). Every call
# site that sets dwm/wallpaper (appearance_menu's animation/custom/wallpaper
# branches, the --wallpaper flag, and sync_ly_wallpaper) must go through
# this instead of calling state_set directly.
# Components flipped on implicitly by select_wallpaper, as opposed to picked
# by the user (checklist/positional/preset). seed_default_components must
# ignore these when deciding whether the user chose components themselves —
# otherwise `--wallpaper doomfire -y` would build only the wallpaper.
declare -gA WALLPAPER_IMPLIED=()

select_wallpaper() {
  local wp="$1" who="${2:-}"
  local setter=state_set; [ "$who" = user ] && setter=user_set
  "$setter" dwm/wallpaper "$wp"
  if is_known_wallpaper "$wp"; then
    "$setter" "component/$wp" on
    WALLPAPER_IMPLIED["component/$wp"]=1
  fi
}

# Loops a tui_menu over appearance settings: a unified animation picker that
# drives both the Ly login animation and the dwm desktop wallpaper together,
# a Desktop wallpaper override item that decouples the two (single-ask:
# "Match login animation (default)" vs. a specific wallpaper — see the
# wallpaper) case below), and the Ly-on-boot checkbox. "off" is the sentinel
# for dwm/wallpaper and ly/animation meaning "none"/unset (see
# apply_configuration/wallpaper_apply).
appearance_menu() {
  while true; do
    local pick
    pick=$(tui_menu "Appearance" "Setting" \
      animation "Animation" wallpaper "Desktop wallpaper" \
      enable "Enable Ly on boot" back "Back") || return 0
    case "$pick" in
      animation)
        local cur sel
        cur=$(state_get ly/animation); [ "$cur" = off ] && cur=none
        sel=$(tui_radiolist "Animation" "Choose login animation (also sets the desktop wallpaper)" \
          doom       "Doom"         "$([ "$cur" = doom ] && echo on || echo off)" \
          matrix     "Matrix"       "$([ "$cur" = matrix ] && echo on || echo off)" \
          gameoflife "Game of Life" "$([ "$cur" = gameoflife ] && echo on || echo off)" \
          colormix   "ColorMix"     "$([ "$cur" = colormix ] && echo on || echo off)" \
          none       "None"         "$([ "$cur" = none ] && echo on || echo off)" \
          custom     "Custom…"      "$([[ "$cur" != doom && "$cur" != matrix && "$cur" != gameoflife && "$cur" != colormix && "$cur" != none ]] && echo on || echo off)") || continue
        if [ "$sel" = custom ]; then
          local name mapped
          name=$(tui_input "Ly animation" "Animation name" "$(state_get ly/animation)") || continue
          # Trim leading/trailing whitespace; an all-whitespace/empty entry
          # is treated as a cancel rather than storing a blank animation.
          name=$(echo "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
          [ -z "$name" ] && continue
          user_set ly/animation "$name"
          if [ -n "${SELECTIONS[ly/match_wallpaper]+x}" ] && ! state_on ly/match_wallpaper; then
            : # explicit desktop override active — leave dwm/wallpaper alone
          else
            mapped=$(ly_animation_to_wallpaper "$name")
            select_wallpaper "$mapped" user
            user_set ly/match_wallpaper on
            # M4: most custom names have no desktop-wallpaper counterpart, but
            # ly_animation_to_wallpaper still recognizes "doom"/"matrix"/
            # "gameoflife"/"colormix" (all also on the radiolist) and
            # "blackhole" (Custom…-only — see lib/wallpaper.sh) typed here —
            # mirror the non-custom branch's messaging instead of
            # unconditionally claiming "set to 'none'" when it wasn't.
            if [ "$mapped" = none ]; then
              tui_msgbox "Appearance" "Custom Ly animations have no desktop wallpaper counterpart yet — desktop wallpaper set to 'none'."
            else
              tui_msgbox "Appearance" "'${name}' matches a known desktop wallpaper — desktop wallpaper set to '${mapped}'."
            fi
          fi
        else
          user_set ly/animation "$sel"
          if [ -n "${SELECTIONS[ly/match_wallpaper]+x}" ] && ! state_on ly/match_wallpaper; then
            : # explicit desktop override active — leave dwm/wallpaper alone
          else
            select_wallpaper "$(ly_animation_to_wallpaper "$sel")" user
            user_set ly/match_wallpaper on
            # Every fixed radiolist entry (doom/matrix/gameoflife/colormix/none)
            # now maps to a real wallpaper or legitimately to "none" — no stub
            # notice needed here. Unmapped names only reach the Custom… branch
            # above, whose own notice covers that case.
          fi
        fi
        ;;
      wallpaper)
        local selw effective
        # Pre-select: "match" when match_wallpaper is on or unset; else the
        # current override value.
        if [ -z "${SELECTIONS[ly/match_wallpaper]+x}" ] || state_on ly/match_wallpaper; then
          effective=match
        else
          effective=$(state_get dwm/wallpaper); [ "$effective" = off ] && effective=none
        fi
        local -a wp_args=(
          match "Match login animation (default)" "$([ "$effective" = match ] && echo on || echo off)"
          none  "None"                            "$([ "$effective" = none ] && echo on || echo off)"
        )
        local w
        while IFS= read -r w; do
          wp_args+=("$w" "${WALLPAPER_DESCS[$w]}" "$([ "$effective" = "$w" ] && echo on || echo off)")
        done < <(available_wallpapers)
        selw=$(tui_radiolist "Desktop wallpaper" "Override the desktop wallpaper, or keep it matched to the login animation" \
          "${wp_args[@]}") || continue
        if [ "$selw" = match ]; then
          user_set ly/match_wallpaper on
          select_wallpaper "$(ly_animation_to_wallpaper "$(state_get ly/animation)")" user
        else
          select_wallpaper "$selw" user
          user_set ly/match_wallpaper off
        fi
        ;;
      enable)
        local cur sel
        if [ -n "${SELECTIONS[ly/enable]+x}" ]; then
          cur=$(state_get ly/enable)
        else
          cur=on   # unset ⇒ effectively "on" (see ly_step_should_run / preview_text's N1)
        fi
        sel=$(tui_radiolist "Ly on boot" "Enable the Ly display manager on boot?" \
          yes "Yes" "$([ "$cur" = on ] && echo on || echo off)" \
          no  "No"  "$([ "$cur" = on ] && echo off || echo on)") || continue
        user_set ly/enable "$([ "$sel" = yes ] && echo on || echo off)"
        ;;
      back|"") return 0 ;;
    esac
  done
}

# reconfigure_read_slstatus CFG_FILE — reads a slstatus config.h(-shaped)
# file and state_sets dwm/interface and dwm/battery to match. Factored out
# of detect_existing_setup so it can be unit-tested against fixture files
# directly. Guarded: a missing file is a no-op.
reconfigure_read_slstatus() {
  local cfg="$1"
  [ -f "$cfg" ] || return 0

  local iface
  iface=$(sed -n 's/.*netspeed_rx.*"\([^"]*\)".*/\1/p' "$cfg" | head -n1)
  [ -n "$iface" ] && state_set dwm/interface "$iface"

  # Mirrors configure_slstatus_battery's toggle: the battery_perc widget
  # entry is commented out (leading "//") when disabled, bare when enabled.
  if grep -Eq '^[[:space:]]*\{[[:space:]]*battery_perc' "$cfg"; then
    state_set dwm/battery on
  elif grep -Eq '^[[:space:]]*//[[:space:]]*\{[[:space:]]*battery_perc' "$cfg"; then
    state_set dwm/battery off
  fi
}

# detect_existing_setup pre-fills SELECTIONS from the live system: a saved
# profile first (if any), then values read straight from the installed
# dwm config / slstatus config / Ly config / xinitrc override it. Every
# file read is guarded so a fresh install (no config.h, no /etc/ly, no
# ~/.xinitrc) is a no-op rather than an error. It also decides whether this
# looks like an existing setup at all (dwm binary on PATH, an Ly config
# file, or ~/.xinitrc) and sets EXISTING_SETUP (0/1) + SETUP_BANNER
# accordingly, for main() to show unconditionally before the main menu.
#
# Two testability seams (both default to real behavior so production
# callers are unaffected): LY_CONFIG_OVERRIDE (default /etc/ly/config.ini)
# is used for both the Ly existence check and the animation read;
# DWM_CHECK_OVERRIDE=missing skips the `command -v dwm` signal.
detect_existing_setup() {
  profile_load "$HOME/.config/manjaro-sl/profile" 2>/dev/null || true

  local found_signal=0

  local cfg="$REPO_ROOT/dwm/config.h"
  [ -f "$cfg" ] || cfg="$REPO_ROOT/dwm/config.def.h"
  if [ -f "$cfg" ]; then
    if grep -q 'define MODKEY Mod4Mask' "$cfg"; then
      state_set dwm/modkey super
    else
      state_set dwm/modkey alt
    fi
    local bar_current
    bar_current=$(sed -n 's/.*col_accent\[\].*= "\([^"]*\)";.*/\1/p' "$cfg" | head -n1)
    [ -n "$bar_current" ] && state_set dwm/barcolor "$bar_current"
  fi

  local slcfg="$REPO_ROOT/slstatus/config.h"
  [ -f "$slcfg" ] || slcfg="$REPO_ROOT/slstatus/config.def.h"
  reconfigure_read_slstatus "$slcfg"

  local ly_config="${LY_CONFIG_OVERRIDE:-/etc/ly/config.ini}"
  if [ -f "$ly_config" ]; then
    found_signal=1
    local a
    a=$(grep -E '^\s*animation\s*=' "$ly_config" 2>/dev/null | sed 's/.*=\s*//' | tr -d ' ' || true)
    [ -n "$a" ] && state_set ly/animation "$a"
    # Newer ly packages ship a per-tty ly@.service instead of ly.service;
    # `systemctl is-enabled 'ly@*.service'` doesn't glob, so check the
    # templated unit via list-unit-files instead.
    if systemctl is-enabled ly.service >/dev/null 2>&1 \
      || systemctl list-unit-files 'ly@*.service' --state=enabled --no-legend 2>/dev/null | grep -q .; then
      state_set ly/enable on
    fi
  fi

  if grep -q 'manjaro-sl wallpaper' "$HOME/.xinitrc" 2>/dev/null; then
    # I2: the launcher's own `exec WP` line is authoritative for which
    # wallpaper is actually wired in — don't guess "doomfire" just because
    # the block exists (that clobbered a preloaded/profile-loaded xmatrix
    # selection). Only fall back to the old doomfire guess when the
    # launcher itself is missing/unreadable (pre-launcher installs where the
    # xinitrc block predates wallpaper.sh writing a launcher script).
    local wp
    wp=$(sed -n 's/^exec //p' "$HOME/.config/manjaro-sl/wallpaper.sh" 2>/dev/null | head -n1 || true)
    if is_known_wallpaper "$wp"; then
      state_set dwm/wallpaper "$wp"
    else
      state_set dwm/wallpaper doomfire
    fi
  else
    state_set dwm/wallpaper none
  fi
  [ -f "$HOME/.xinitrc" ] && found_signal=1

  if [ "${DWM_CHECK_OVERRIDE:-}" != missing ] && command -v dwm >/dev/null 2>&1; then
    found_signal=1
  fi

  EXISTING_SETUP=$found_signal
  if [ "$EXISTING_SETUP" -eq 1 ]; then
    SETUP_BANNER="existing setup detected — current settings loaded"
  else
    SETUP_BANNER="fresh setup"
  fi
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
  out+="WALLPAPER:\n  ${wp}\n\n"

  local ly_anim; ly_anim=$(state_get ly/animation); [ "$ly_anim" = "off" ] && ly_anim="none"

  # N1: state_get can't distinguish "never set" from "explicitly off" (both
  # read as "off"), but apply behaves differently for the two — unset
  # ly/enable still enables Ly (legacy build_suckless.sh behavior; see
  # ly_step_should_run/configure_ly_display_manager's C2 comment), while an
  # explicit off skips it. Mirror that here with the same
  # ${SELECTIONS[ly/enable]+x} set-check lib/ly.sh's C2 gate uses, so the
  # preview doesn't lie about what apply will actually do.
  local ly_enable_display
  if [ -n "${SELECTIONS[ly/enable]+x}" ]; then
    ly_enable_display=$(state_get ly/enable)
  else
    ly_enable_display="on (default)"
  fi
  out+="LY:\n  enable=${ly_enable_display} animation=${ly_anim} match_wallpaper=$(state_get ly/match_wallpaper)\n\n"

  # FILES reflects the same effective xinitrc/dwm.desktop copy defaults
  # apply_configuration will use (I3: -y/LEGACY_Y defaults both to "no",
  # interactive TUI apply defaults both to "yes"; explicit --copy-*/
  # --no-copy-* flags already set COPY_XINIT/COPY_DESKTOP and always win).
  local files_xinit="${COPY_XINIT:-}" files_desktop="${COPY_DESKTOP:-}"
  if [ -z "$files_xinit" ]; then
    files_xinit=$([ "${LEGACY_Y:-0}" -eq 1 ] && echo no || echo yes)
  fi
  if [ -z "$files_desktop" ]; then
    files_desktop=$([ "${LEGACY_Y:-0}" -eq 1 ] && echo no || echo yes)
  fi
  out+="FILES:\n  xinitrc=${files_xinit} dwm.desktop=${files_desktop}"

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
  # Legacy parity: `-y` (LEGACY_Y) is old build_suckless.sh -y, which
  # defaulted both copies to "no" (see setup_misc_files' own ACCEPT_DEFAULTS
  # branch); interactive TUI Preview & Apply runs default to "yes" as
  # before. Explicit --copy-*/--no-copy-* flags (COPY_XINIT/COPY_DESKTOP
  # already set by parse_args) always win over either default.
  if [ "$LEGACY_Y" -eq 1 ]; then
    COPY_XINIT=${COPY_XINIT:-no}
    COPY_DESKTOP=${COPY_DESKTOP:-no}
  else
    COPY_XINIT=${COPY_XINIT:-yes}
    COPY_DESKTOP=${COPY_DESKTOP:-yes}
  fi
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

# run_step's subshell isolation (see apply_configuration's comment above)
# means a state_set made inside one run_step call never reaches the next
# one. appearance_menu's unified Animation picker (and its match_wallpaper
# on/off toggling) is normally applied inline when set interactively, but
# during Preview & Apply nothing ever runs appearance_menu — so this
# parent-shell sync must happen once, before any run_step call, or the dwm
# wallpaper implied by ly/match_wallpaper is lost.
sync_ly_wallpaper() {
  if state_on ly/match_wallpaper; then
    select_wallpaper "$(ly_animation_to_wallpaper "$(state_get ly/animation)")"
  fi
}

# Debloat/tweaks/install-packages route every mutating command through
# run_mut, so --dry-run is safe there already. Build/Configure/Ly/Wallpaper
# don't (they write dwm/slstatus config.h, ~/.xinitrc, /etc/ly/config.ini,
# and toggle systemd units directly via run_with_privilege/python3/sudo) —
# rewiring each call site is out of scope here, so under --dry-run these
# _maybe wrappers skip the real step entirely and print a note instead,
# guaranteeing `--dry-run --apply` never touches the real system.
dry_run_note() { echo "[dry-run] skipping ${1} (writes files/services directly, not wired through run_mut)"; }

build_selected_components_maybe() {
  if [ "$DRY_RUN" -eq 1 ]; then
    local -a comps=()
    local key
    for key in "${!SELECTIONS[@]}"; do
      [[ "$key" == component/* ]] && [ "${SELECTIONS[$key]}" = on ] && comps+=("${key#component/}")
    done
    dry_run_note "Build components (selected: ${comps[*]:-none})"
    return 0
  fi
  build_selected_components
}

apply_configuration_maybe() {
  [ "$DRY_RUN" -eq 1 ] && { dry_run_note "Configure"; return 0; }
  apply_configuration
}

configure_ly_display_manager_maybe() {
  [ "$DRY_RUN" -eq 1 ] && { dry_run_note "Ly"; return 0; }
  configure_ly_display_manager
}

wallpaper_apply_maybe() {
  [ "$DRY_RUN" -eq 1 ] && { dry_run_note "Wallpaper"; return 0; }
  wallpaper_apply
}

# Fixed order: debloat → tweaks → install → build → configure → ly →
# wallpaper → summary, each via run_step so failures offer continue/abort.
# Each step is additionally gated by section_enabled (see --only), the
# install step by SKIP_PACKAGES (see --skip-packages), and the Ly step
# additionally by ly_step_should_run (see N2 comment above) so a bare
# per-component rebuild that doesn't include dwm doesn't also flip the
# system's display manager.
apply_all() {
  ACCEPT_DEFAULTS=1
  sync_ly_wallpaper
  section_enabled debloat && run_step "Debloat"           debloat_apply
  section_enabled tweaks  && run_step "System tweaks"     tweaks_apply
  if section_enabled install; then
    [ "$SKIP_PACKAGES" -eq 0 ] && run_step "Install packages" install_selected_packages
    run_step "Build components" build_selected_components_maybe
  fi
  section_enabled dwm && run_step "Configure" apply_configuration_maybe
  section_enabled ly && ly_step_should_run && run_step "Ly" configure_ly_display_manager_maybe
  section_enabled dwm && run_step "Wallpaper" wallpaper_apply_maybe
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] skipping profile save"
  else
    profile_save "$HOME/.config/manjaro-sl/profile"
  fi
  tui_msgbox "Done" "All steps finished. Log: ${RUN_LOG:-none}\nReboot to switch to Ly + dwm."
}

main_menu() {
  while true; do
    local pick
    pick=$(tui_menu "manjaro-sl" "$SETUP_BANNER — Main menu" \
      desktop "Desktop Setup"  appearance "Appearance" \
      debloat "Debloat Manjaro"  tweaks "System Tweaks" \
      preset "Presets"  apply "Preview & Apply"  quit "Quit") || pick=quit
    case "$pick" in
      desktop)    desktop_setup_menu ;;
      appearance) appearance_menu ;;
      debloat)    debloat_menu ;;
      tweaks)     tweaks_screen ;;
      preset)     local p; p=$(tui_radiolist "Preset" "Choose" \
                    recommended       "Recommended (keeps your changes)"        on \
                    minimal           "Minimal (keeps your changes)"            off \
                    reset-recommended "Recommended — overwrite everything"      off \
                    reset-minimal     "Minimal — overwrite everything"          off) && \
                    case "$p" in
                      reset-*) preset_apply "${p#reset-}" reset ;;
                      recommended|minimal) preset_apply "$p" baseline ;;
                    esac ;;
      apply)      if tui_yesno "Preview" "$(preview_text)\n\nApply now?"; then apply_all; fi ;;
      quit|"")    break ;;
    esac
  done
}

# parse_args processes argv left-to-right, building up SELECTIONS/globals
# exactly like the TUI screens do. Because it's strictly sequential,
# `--preset` bulk-sets selections at the point it's parsed — any
# --enable-*/--disable-* (or other selection-setting) flag placed AFTER it
# on the command line overrides what the preset chose; flags placed before
# a --preset get overridden by it instead. See usage().
parse_args() {
  while (($#)); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --preset)
        [ $# -ge 2 ] || { echo "Error: --preset requires a value." >&2; exit 1; }
        case "$2" in
          recommended|minimal) preset_apply "$2" ;;
          *) echo "Error: --preset must be 'recommended' or 'minimal'." >&2; exit 1 ;;
        esac
        shift
        ;;
      --only)
        [ $# -ge 2 ] || { echo "Error: --only requires a value." >&2; exit 1; }
        case "$2" in
          install|debloat|tweaks|dwm|ly) ONLY_SECTIONS+=("$2") ;;
          *) echo "Error: --only must be one of install|debloat|tweaks|dwm|ly." >&2; exit 1 ;;
        esac
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --profile)
        [ $# -ge 2 ] || { echo "Error: --profile requires a value." >&2; exit 1; }
        profile_load "$2" || { echo "Error: profile file not found: $2" >&2; exit 1; }
        shift
        ;;
      --apply)
        APPLY_NOW=1
        ;;
      --wallpaper)
        [ $# -ge 2 ] || { echo "Error: --wallpaper requires a value." >&2; exit 1; }
        if [ "$2" = none ] || { is_known_wallpaper "$2" && [ -d "$REPO_ROOT/$2" ]; }; then
          select_wallpaper "$2"
        else
          echo "Error: --wallpaper must be 'none' or one of: $(available_wallpapers | tr '\n' ' ' | sed 's/ $//')." >&2
          exit 1
        fi
        shift
        ;;
      --interface)
        [ $# -ge 2 ] || { echo "Error: --interface requires a value." >&2; exit 1; }
        state_set dwm/interface "$2"
        shift
        ;;
      --battery)
        state_set dwm/battery on
        ;;
      --no-battery)
        state_set dwm/battery off
        ;;
      --bar-color)
        [ $# -ge 2 ] || { echo "Error: --bar-color requires a value." >&2; exit 1; }
        state_set dwm/barcolor "$2"
        shift
        ;;
      --modkey)
        [ $# -ge 2 ] || { echo "Error: --modkey requires a value (super or alt)." >&2; exit 1; }
        case "$2" in
          super|alt) state_set dwm/modkey "$2" ;;
          *) echo "Error: --modkey must be 'super' or 'alt'." >&2; exit 1 ;;
        esac
        shift
        ;;
      --remove-de)
        # Reuses preset_apply minimal's guarded pattern: only mark old
        # DEs/DMs actually installed, and stay a no-op without pacman.
        if declare -F debloat_installed_from >/dev/null && command -v pacman >/dev/null 2>&1; then
          local f
          for f in "$REPO_ROOT/data/de.list" "$REPO_ROOT/data/dm.list"; do
            while IFS='|' read -r name desc state; do state_set "debloat/$name" on; done < <(debloat_installed_from "$f")
          done
        fi
        ;;
      --no-remove-de)
        echo "Note: --no-remove-de is the default; old DEs/DMs are left untouched unless --remove-de is passed."
        ;;
      -y|--accept-defaults)
        Y_FLAG=1
        LEGACY_Y=1
        TUI_ACTIVE=0
        ;;
      --skip-packages)
        SKIP_PACKAGES=1
        ;;
      --copy-xinit)
        COPY_XINIT=yes
        ;;
      --no-copy-xinit)
        COPY_XINIT=no
        ;;
      --copy-desktop)
        COPY_DESKTOP=yes
        ;;
      --no-copy-desktop)
        COPY_DESKTOP=no
        ;;
      --enable-*|--disable-*)
        local flag mode slug found=0 f
        flag=${1#--}; mode=${flag%%-*}; slug=${flag#*-}
        for f in "$REPO_ROOT"/data/debloat-*.list; do
          if list_entries "$f" | cut -d'|' -f1 | grep -qx "$slug"; then
            state_set "debloat/$slug" "$([ "$mode" = enable ] && echo on || echo off)"
            found=1
          fi
        done
        if list_entries "$REPO_ROOT/data/install-recommended.list" | cut -d'|' -f1 | grep -qx "$slug"; then
          state_set "install/$slug" "$([ "$mode" = enable ] && echo on || echo off)"
          found=1
        fi
        [ "$found" -eq 0 ] && { echo "Unknown flag: $1" >&2; exit 1; }
        ;;
      -*)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
      *)
        # Legacy positional component name (build_suckless.sh muscle memory,
        # e.g. `./manjaro-sl.sh st`). Validated and applied once the whole
        # argv has been consumed — see below.
        POSITIONAL_COMPONENTS+=("$1")
        ;;
    esac
    shift
  done

  # Positional component names, if any, are validated and applied last —
  # after any --preset on the command line has bulk-set its own component
  # selection — so `./manjaro-sl.sh --preset minimal st` builds only st,
  # consistent with the left-to-right-then-positionals rule documented in
  # usage(): later selections win.
  if [ ${#POSITIONAL_COMPONENTS[@]} -gt 0 ]; then
    local -a valid_comps=(dwm dmenu st slstatus)
    local w
    while IFS= read -r w; do valid_comps+=("$w"); done < <(available_wallpapers)
    local pc c ok
    for pc in "${POSITIONAL_COMPONENTS[@]}"; do
      ok=0
      for c in "${valid_comps[@]}"; do [ "$c" = "$pc" ] && { ok=1; break; }; done
      if [ "$ok" -eq 0 ]; then
        echo "Unknown component: $pc (valid: ${valid_comps[*]})" >&2
        exit 1
      fi
    done
    for c in "${valid_comps[@]}"; do state_set "component/$c" off; done
    for pc in "${POSITIONAL_COMPONENTS[@]}"; do state_set "component/$pc" on; done
  fi
}

# seed_default_components — if selections carry no USER-chosen component/*
# key (bare/legacy runs with no --preset and no positional component names),
# seed the legacy DEFAULT_COMPONENTS set (dwm dmenu st slstatus — NOT
# doomfire, matching old build_suckless.sh) so "Build components" isn't
# silently left empty. Presets and positional component args both set
# component/* keys themselves, so this is a no-op whenever either was used.
# Keys implied by select_wallpaper (WALLPAPER_IMPLIED) don't count as a user
# choice — `--wallpaper doomfire -y` must still build the default desktop —
# and seeding is additive on top of them; called once selections are
# finalized, before dispatching to the TUI or apply_all.
seed_default_components() {
  local key
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == component/* ]] || continue
    [ -n "${WALLPAPER_IMPLIED[$key]:-}" ] && continue
    return 0
  done
  local c
  for c in dwm dmenu st slstatus; do state_set "component/$c" on; done
}

main() {
  if [ "$#" -gt 0 ]; then
    parse_args "$@"
    # -y is old build_suckless.sh shorthand for "run non-interactively with
    # current settings"; keep that parity by having it imply --apply unless
    # --apply was already given explicitly.
    if [ "$Y_FLAG" -eq 1 ] && [ "$APPLY_NOW" -eq 0 ]; then
      APPLY_NOW=1
    fi
  fi
  seed_default_components
  if [ "$APPLY_NOW" -eq 1 ]; then
    TUI_ACTIVE=0
    sanity_checks
    apply_all
  else
    sanity_checks
    detect_existing_setup
    main_menu
  fi
}

# Guard so sourcing this file (tests, `bash -c 'source manjaro-sl.sh'` syntax
# checks) only defines the functions above without launching the TUI.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
