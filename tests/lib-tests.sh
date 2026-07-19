#!/usr/bin/env bash
# Sourced by run-tests.sh. REPO_ROOT is set by the runner.
source "$REPO_ROOT/lib/exec.sh"

# run_mut in dry-run mode prints instead of executing
DRY_RUN=1
out=$(run_mut touch /tmp/manjaro-sl-should-never-exist)
assert_contains "$out" "+ touch /tmp/manjaro-sl-should-never-exist"
assert_fail test -e /tmp/manjaro-sl-should-never-exist

# run_mut executes when DRY_RUN=0
DRY_RUN=0
tmpf=$(mktemp -u)
run_mut touch "$tmpf" >/dev/null
assert_ok test -e "$tmpf"
rm -f "$tmpf"

# M3: DRY_RUN normalization — an unknown truthy value like "true" (e.g. from
# a caller's environment) must be treated as dry-run (1), the conservative
# direction, never silently as live (0). Re-source lib/exec.sh since the
# DRY_RUN=${DRY_RUN:-0} default + normalization case only run at source
# time, not on every run_mut call.
DRY_RUN=true
source "$REPO_ROOT/lib/exec.sh"
assert_eq "$DRY_RUN" "1"
out=$(run_mut touch /tmp/manjaro-sl-should-never-exist-2)
assert_contains "$out" "+ touch /tmp/manjaro-sl-should-never-exist-2"
assert_fail test -e /tmp/manjaro-sl-should-never-exist-2
DRY_RUN=0
source "$REPO_ROOT/lib/exec.sh"

# log_dir creates and echoes the state dir
d=$(XDG_STATE_HOME=$(mktemp -d) log_dir)
assert_ok test -d "$d"
assert_contains "$d" "manjaro-sl"

# run_step detects failure even without caller pipefail (regression)
step_fail() { return 7; }
# Test 1: failing step with "n" (abort) should return nonzero, not swallowed by pipeline
(
  set +o pipefail
  XDG_STATE_HOME=$(mktemp -d)
  RUN_LOG=""
  run_step "test_fail" step_fail <<< "n" >/dev/null 2>&1
)
assert_fail test "$?" -eq 0
# Test 2: failing step with "y" (continue) should return 0
(
  set +o pipefail
  XDG_STATE_HOME=$(mktemp -d)
  RUN_LOG=""
  run_step "test_fail" step_fail <<< "y" >/dev/null 2>&1
)
assert_ok test "$?" -eq 0

source "$REPO_ROOT/lib/state.sh"

# list parsing strips comments/blanks
entries=$(list_entries "$REPO_ROOT/data/debloat-bluetooth.list")
assert_contains "$entries" "bluez|Bluetooth stack|off"
assert_eq "$(echo "$entries" | grep -c '^#')" "0"

# selections
state_set "debloat/bluez" on
assert_eq "$(state_get debloat/bluez)" "on"
assert_eq "$(state_get missing/key)" "off"
assert_ok state_on debloat/bluez
assert_fail state_on missing/key

# denylist blocks criticals incl. globs
assert_ok denylisted manjaro-keyring
assert_ok denylisted mhwd-nvidia-580xx
assert_ok denylisted linux-lts
assert_fail denylisted manjaro-hello

# profile round-trip
pf=$(mktemp)
profile_save "$pf"
unset SELECTIONS; declare -gA SELECTIONS
profile_load "$pf"
assert_eq "$(state_get debloat/bluez)" "on"
rm -f "$pf"

# profile_save creates missing parent directories (regression: apply_all died
# at the final save when ~/.config/manjaro-sl didn't exist yet)
pd=$(mktemp -d)
assert_ok profile_save "$pd/newdir/profile"
assert_ok test -f "$pd/newdir/profile"
rm -rf "$pd"

# preset_apply: recommended — file defaults for debloat-manjaro, apps stay
# off, recommended installs on, doomfire wallpaper + doom ly animation
unset SELECTIONS; declare -gA SELECTIONS
preset_apply recommended
assert_eq "$(state_get debloat/manjaro-hello)" "on"
assert_eq "$(state_get debloat/pamac-gtk3)" "off"
assert_eq "$(state_get install/feh)" "on"
assert_eq "$(state_get dwm/wallpaper)" "doomfire"
assert_eq "$(state_get ly/animation)" "doom"

# preset_apply: minimal — everything (except warned items) removed, no
# recommended installs, no wallpaper, but components still on
unset SELECTIONS; declare -gA SELECTIONS
preset_apply minimal
assert_eq "$(state_get debloat/pamac-gtk3)" "on"
assert_eq "$(state_get debloat/timeshift)" "off"
assert_eq "$(state_get install/feh)" "off"
assert_eq "$(state_get dwm/wallpaper)" "none"
assert_eq "$(state_get component/dwm)" "on"

source "$REPO_ROOT/lib/tui.sh"
TUI_ACTIVE=0   # force fallback path for tests

out=$(tui_menu "T" "Pick" a "Alpha" b "Beta" <<< "2")
assert_eq "$out" "b"

out=$(tui_radiolist "T" "Pick" x "Xray" off y "Yankee" on <<< "")
assert_eq "$out" "y"   # empty input keeps default

out=$(tui_checklist "T" "Pick" p "Pkg1" on q "Pkg2" off <<< "")
assert_eq "$out" "p"   # defaults preserved on empty input

assert_ok  tui_yesno "T" "sure?" <<< "y"
assert_fail tui_yesno "T" "sure?" <<< "n"

out=$(tui_input "T" "Color" "#112233" <<< "")
assert_eq "$out" "#112233"

# --help must work even when sudo is not on PATH (fresh-install scenario)
nosudo_dir=$(mktemp -d)
for tool in bash grep sed awk cat head tr mktemp date basename dirname id find ip; do
  p=$(command -v "$tool" 2>/dev/null) && ln -sf "$p" "$nosudo_dir/$tool"
done

# manjaro-sl.sh --help must also work without sudo on PATH (regression: the
# sourcing order must put -h/--help handling before lib/common.sh, which
# exits 1 if sudo is missing)
out=$(env -i PATH="$nosudo_dir" HOME="$HOME" bash "$REPO_ROOT/manjaro-sl.sh" --help 2>&1); rc=$?
assert_eq "$rc" "0"
assert_contains "$out" "Usage:"
rm -rf "$nosudo_dir"

source "$REPO_ROOT/lib/debloat.sh"

# filtering: fake pacman that says only 'bluez' is installed
pacman() { [ "$1" = "-Qq" ] && { [ "$2" = "bluez" ]; return; }; command pacman "$@"; }
out=$(debloat_installed_from "$REPO_ROOT/data/debloat-bluetooth.list")
assert_contains "$out" "bluez|"
assert_eq "$(echo "$out" | grep -c blueman)" "0"

# denylist enforcement in apply: selecting a denylisted pkg must be refused
declare -gA SELECTIONS=()
state_set "debloat/manjaro-keyring" on
state_set "debloat/bluez" on
DRY_RUN=1
out=$(debloat_apply)
assert_contains "$out" "REFUSED (denylist): manjaro-keyring"
assert_contains "$out" "+ sudo pacman -Rns"
assert_contains "$out" "bluez"
unset -f pacman

# I1: ACCEPT_DEFAULTS=1 (non-interactive -y/--apply runs) must pass
# --noconfirm to the removal command too, mirroring lib/packages.sh's
# install path — otherwise pacman -Rns's confirmation prompt blocks forever
# with no one at the terminal to answer it.
declare -gA SELECTIONS=()
state_set "debloat/bluez" on
DRY_RUN=1
ACCEPT_DEFAULTS=1
out=$(debloat_apply)
assert_contains "$out" "+ sudo pacman -Rns --noconfirm"
assert_contains "$out" "bluez"
ACCEPT_DEFAULTS=0

# preset_apply minimal marks installed old DEs/DMs for removal; recommended
# leaves them untouched ("prompt" per the spec's preset table)
pacman() { [ "$1" = "-Qq" ] && { [ "$2" = "sddm" ]; return; }; command pacman "$@"; }
unset SELECTIONS; declare -gA SELECTIONS
preset_apply minimal
assert_eq "$(state_get debloat/sddm)" "on"
unset SELECTIONS; declare -gA SELECTIONS
preset_apply recommended
assert_eq "$(state_get debloat/sddm)" "off"
unset -f pacman

source "$REPO_ROOT/lib/tweaks.sh"
declare -gA SELECTIONS=()
state_set "tweak/enable:fstrim.timer" on
state_set "tweak/disable:cups.service" on
DRY_RUN=1
out=$(tweaks_apply)
assert_contains "$out" "+ sudo systemctl enable fstrim.timer"
assert_contains "$out" "+ sudo systemctl disable cups.service"

source "$REPO_ROOT/lib/wallpaper.sh"
declare -gA SELECTIONS=()
DRY_RUN=0
OLD_HOME=$HOME
export HOME=$(mktemp -d); mkdir -p "$HOME"

state_set dwm/wallpaper doomfire
wallpaper_apply
assert_ok test -x "$HOME/.config/manjaro-sl/wallpaper.sh"
assert_contains "$(cat "$HOME/.xinitrc")" "# >>> manjaro-sl wallpaper >>>"
assert_contains "$(cat "$HOME/.config/manjaro-sl/wallpaper.sh")" "doomfire"

# idempotent: applying twice leaves exactly one block
wallpaper_apply
assert_eq "$(grep -c 'manjaro-sl wallpaper >>>' "$HOME/.xinitrc")" "1"

# none removes the block
state_set dwm/wallpaper none
wallpaper_apply
assert_eq "$(grep -c 'manjaro-sl wallpaper' "$HOME/.xinitrc" || true)" "0"

# append branch: file without trailing newline and without exec dwm must stay idempotent
declare -gA SELECTIONS=()
state_set dwm/wallpaper doomfire
printf 'exec bash' > "$HOME/.xinitrc"     # no trailing newline, no dwm line
wallpaper_apply
wallpaper_apply
assert_eq "$(grep -c 'manjaro-sl wallpaper >>>' "$HOME/.xinitrc")" "1"
assert_contains "$(head -n1 "$HOME/.xinitrc")" "exec bash"

assert_eq "$(ly_animation_to_wallpaper doom)" "doomfire"
assert_eq "$(ly_animation_to_wallpaper matrix)" "xmatrix"
assert_eq "$(ly_animation_to_wallpaper colormix)" "none"

# regression: the awk insert-before-exec-dwm path must preserve the execute
# bit — Ly runs ~/.xinitrc as a program, so dropping +x locks the user out
printf '#!/usr/bin/env bash\nexec dwm\n' > "$HOME/.xinitrc"
chmod 755 "$HOME/.xinitrc"
state_set dwm/wallpaper doomfire
wallpaper_apply
assert_ok test -x "$HOME/.xinitrc"
assert_eq "$(grep -c 'manjaro-sl wallpaper >>>' "$HOME/.xinitrc")" "1"

HOME=$OLD_HOME

# wallpaper registry
assert_ok is_known_wallpaper doomfire
assert_ok is_known_wallpaper xblackhole
assert_fail is_known_wallpaper spinningcube
# available = registry ∩ existing dirs; right now only doomfire+xmatrix exist
avail=$(available_wallpapers | tr '\n' ' ')
assert_eq "$avail" "doomfire xmatrix xcolormix "
# every registry member has a description
for w in "${KNOWN_WALLPAPERS[@]}"; do
  assert_ok test -n "${WALLPAPER_DESCS[$w]:-}"
done

# --wallpaper flag accepts xmatrix (usage() advertises it) and still
# rejects unknown values
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --wallpaper xmatrix --dry-run --apply --skip-packages 2>&1); rc=$?
assert_eq "$rc" "0"
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --wallpaper spinningcube --dry-run --apply 2>&1); rc=$?
assert_eq "$rc" "1"
assert_contains "$out" "--wallpaper must be"
rm -rf "$t_home" "$t_state"

# manjaro-sl.sh: preview_text renders grouped SELECTIONS. Sourced in a
# subshell (bash -c) since manjaro-sl.sh sets `set -euo pipefail` at its own
# top, which must not leak into this (non -e) test runner's shell.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  preview_text
')
assert_contains "$out" "REMOVE:"
assert_contains "$out" "INSTALL:"
assert_contains "$out" "BUILD:"
assert_contains "$out" "CONFIGURE:"
assert_contains "$out" "TWEAKS:"
assert_contains "$out" "WALLPAPER:"
assert_contains "$out" "(none)"

out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  state_set debloat/manjaro-hello on
  state_set install/feh on
  state_set component/dwm on
  state_set dwm/modkey super
  state_set "tweak/enable:fstrim.timer" on
  state_set dwm/wallpaper doomfire
  preview_text
')
assert_contains "$out" "manjaro-hello"
assert_contains "$out" "feh"
assert_contains "$out" "modkey=super"
assert_contains "$out" "enable:fstrim.timer"
assert_contains "$out" "doomfire"

# apply_all's run_step subshells can't propagate cross-step state_set calls
# (see apply_configuration's comment), so the ly/match_wallpaper -> dwm/
# wallpaper sync must happen in the parent shell before any run_step call.
# sync_ly_wallpaper is that parent-shell sync, factored out for testability.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  state_set ly/match_wallpaper on
  state_set ly/animation doom
  sync_ly_wallpaper
  state_get dwm/wallpaper
')
assert_eq "$out" "doomfire"

# no sync when match_wallpaper is off
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  state_set ly/match_wallpaper off
  state_set ly/animation doom
  sync_ly_wallpaper
  state_get dwm/wallpaper
')
assert_eq "$out" "off"

source "$REPO_ROOT/lib/ly.sh"

# Gap A: configure_ly_display_manager must write the TUI-chosen animation
# even under ACCEPT_DEFAULTS=1 (Preview & Apply / apply_all), not just in
# the interactive prompt path. Mock everything that would otherwise touch
# the real system.
pacman() { [ "$1" = "-Qi" ] && [ "$2" = "ly" ]; }
systemctl() { return 1; }
run_with_privilege() { echo "RWP: $*"; }
require_command() { :; }
unset SELECTIONS; declare -gA SELECTIONS
ACCEPT_DEFAULTS=1
state_set ly/animation matrix
out=$(configure_ly_display_manager 2>&1)
assert_contains "$out" "Updating animation to: matrix"
assert_contains "$out" "RWP: python3 - /etc/ly/config.ini matrix"

# ...but not when no animation was selected (state absent/off)
unset SELECTIONS; declare -gA SELECTIONS
ACCEPT_DEFAULTS=1
out=$(configure_ly_display_manager 2>&1)
assert_eq "$(echo "$out" | grep -c 'Updating animation to')" "0"

# C2: ly/enable is write-only otherwise — configure_ly_display_manager used
# to unconditionally enable+start Ly regardless of the ly/enable checkbox.
# Explicitly off must skip both, with a one-line note; run_with_privilege is
# mocked to just echo (not actually invoke systemctl), so grepping its
# recorded calls proves enable/start were never attempted.
unset SELECTIONS; declare -gA SELECTIONS
ACCEPT_DEFAULTS=1
state_set ly/enable off
out=$(configure_ly_display_manager 2>&1)
assert_contains "$out" "skipping Ly service enable/start"
assert_eq "$(echo "$out" | grep -c 'RWP: systemctl enable')" "0"
assert_eq "$(echo "$out" | grep -c 'RWP: systemctl start')" "0"

# ly/enable left unset (never explicitly set, as opposed to explicitly
# "off") must keep today's behavior: enable is still attempted. state_get
# alone can't tell these apart (both read as "off"), which is exactly the
# bug the SELECTIONS-array check above guards against.
unset SELECTIONS; declare -gA SELECTIONS
ACCEPT_DEFAULTS=1
out=$(configure_ly_display_manager 2>&1)
assert_contains "$out" "RWP: systemctl enable"

unset -f pacman systemctl run_with_privilege require_command

# --- Task 10: CLI flags, non-interactive mode, reconfigure mode ---------

source "$REPO_ROOT/lib/packages.sh"

# ensure_recommended_packages must route its mutating pacman call through
# run_mut (dry-run aware) rather than run_with_privilege directly, so
# `--dry-run` never actually installs anything. run_mut is already defined
# (lib/exec.sh was sourced at the top of this file), matching how
# manjaro-sl.sh sources it before lib/packages.sh.
pacman() {
  case "$1" in
    -Sg) return 1 ;;
    -Qi) [ "$2" = "already-here" ] ;;
  esac
}
ACCEPT_DEFAULTS=1
CHECK_PACKAGES=1
RECOMMENDED_PACKAGES=(totally-missing-pkg)
BUILD_PACKAGES=(already-here)
DRY_RUN=1
out=$(ensure_recommended_packages 2>&1)
assert_contains "$out" "+ sudo pacman -Syu --needed --noconfirm totally-missing-pkg"
DRY_RUN=0
unset -f pacman

# parse_args: legacy flags map onto dwm/* SELECTIONS + globals; --enable-*/
# --disable-* toggle debloat/install entries by slug; --only is repeatable
# and section_enabled reflects it; --dry-run sets DRY_RUN.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  parse_args --interface eth0 --battery --bar-color "#112233" --modkey super \
    --wallpaper doomfire --skip-packages --copy-xinit --no-copy-desktop \
    --enable-bluez --disable-feh --only debloat --only ly --dry-run
  echo "interface=$(state_get dwm/interface)"
  echo "battery=$(state_get dwm/battery)"
  echo "barcolor=$(state_get dwm/barcolor)"
  echo "modkey=$(state_get dwm/modkey)"
  echo "wallpaper=$(state_get dwm/wallpaper)"
  echo "skip=$SKIP_PACKAGES"
  echo "copyxinit=$COPY_XINIT"
  echo "copydesktop=$COPY_DESKTOP"
  echo "bluez=$(state_get debloat/bluez)"
  echo "feh=$(state_get install/feh)"
  echo "dryrun=$DRY_RUN"
  section_enabled debloat && echo "debloat_section=yes"
  section_enabled ly && echo "ly_section=yes"
  section_enabled install || echo "install_section=no"
')
assert_contains "$out" "interface=eth0"
assert_contains "$out" "battery=on"
assert_contains "$out" 'barcolor=#112233'
assert_contains "$out" "modkey=super"
assert_contains "$out" "wallpaper=doomfire"
assert_contains "$out" "skip=1"
assert_contains "$out" "copyxinit=yes"
assert_contains "$out" "copydesktop=no"
assert_contains "$out" "bluez=on"
assert_contains "$out" "feh=off"
assert_contains "$out" "dryrun=1"
assert_contains "$out" "debloat_section=yes"
assert_contains "$out" "ly_section=yes"
assert_contains "$out" "install_section=no"

# --no-battery / --no-remove-de / --no-copy-xinit / --copy-desktop and the
# --no-remove-de note
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  parse_args --no-battery --no-remove-de --no-copy-xinit --copy-desktop
  echo "battery=$(state_get dwm/battery)"
  echo "copyxinit=$COPY_XINIT"
  echo "copydesktop=$COPY_DESKTOP"
' 2>&1)
assert_contains "$out" "battery=off"
assert_contains "$out" "copyxinit=no"
assert_contains "$out" "copydesktop=yes"
assert_contains "$out" "Note: --no-remove-de is the default"

# --remove-de reuses debloat_installed_from to mark only installed old
# DEs/DMs (guarded pattern from preset_apply minimal); mock pacman to say
# only sddm is installed.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  pacman() { [ "$1" = "-Qq" ] && [ "$2" = "sddm" ]; }
  parse_args --remove-de
  state_get debloat/sddm
')
assert_eq "$out" "on"

# --preset applies preset_apply immediately when parsed; flags AFTER it
# override what the preset chose (later wins, strict left-to-right).
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  parse_args --preset minimal --disable-manjaro-hello
  state_get debloat/manjaro-hello
')
assert_eq "$out" "off"
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  parse_args --disable-manjaro-hello --preset minimal
  state_get debloat/manjaro-hello
')
assert_eq "$out" "on"

# Unknown/invalid flags exit 1 with an error (subprocess: exercises the
# real -h-before-common.sh sourcing order + full parse_args error paths).
out=$("$REPO_ROOT/manjaro-sl.sh" --bogus-flag 2>&1); rc=$?
assert_eq "$rc" "1"; assert_contains "$out" "Unknown option: --bogus-flag"

out=$("$REPO_ROOT/manjaro-sl.sh" --preset bogus 2>&1); rc=$?
assert_eq "$rc" "1"; assert_contains "$out" "Error: --preset must be"

out=$("$REPO_ROOT/manjaro-sl.sh" --profile /no/such/file 2>&1); rc=$?
assert_eq "$rc" "1"; assert_contains "$out" "profile file not found"

out=$("$REPO_ROOT/manjaro-sl.sh" --enable-not-a-real-package 2>&1); rc=$?
assert_eq "$rc" "1"; assert_contains "$out" "Unknown flag: --enable-not-a-real-package"

out=$("$REPO_ROOT/manjaro-sl.sh" --only bogus 2>&1); rc=$?
assert_eq "$rc" "1"

out=$("$REPO_ROOT/manjaro-sl.sh" --modkey bogus 2>&1); rc=$?
assert_eq "$rc" "1"

out=$("$REPO_ROOT/manjaro-sl.sh" --wallpaper bogus 2>&1); rc=$?
assert_eq "$rc" "1"

out=$("$REPO_ROOT/manjaro-sl.sh" --help 2>&1); rc=$?
assert_eq "$rc" "0"; assert_contains "$out" "Usage:"

# main() dispatch: --apply (or -y, which implies --apply unless already
# given) skips the TUI and calls apply_all; plain flags without either
# still fall through to the interactive main_menu.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  sanity_checks() { :; }
  apply_all() { echo "apply_all called"; }
  main_menu() { echo "main_menu called"; }
  main -y
')
assert_contains "$out" "apply_all called"
assert_eq "$(echo "$out" | grep -c "main_menu called")" "0"

out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  sanity_checks() { :; }
  apply_all() { echo "apply_all called"; }
  main_menu() { echo "main_menu called"; }
  main --preset minimal
')
assert_contains "$out" "main_menu called"
assert_eq "$(echo "$out" | grep -c "apply_all called")" "0"

# sanity_checks must not offer to install whiptail (no prompt, no stdin
# read) when running non-interactively via --apply/-y; it should just fall
# back to TUI_ACTIVE=0.
out=$(TUI_ACTIVE=1 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  tui_available() { return 1; }
  APPLY_NOW=1
  sanity_checks
  echo "TUI_ACTIVE=$TUI_ACTIVE"
' 2>&1 </dev/null)
assert_contains "$out" "TUI_ACTIVE=0"
assert_eq "$(echo "$out" | grep -c 'Install libnewt')" "0"

# detect_existing_setup pre-fills SELECTIONS from the live system: dwm/config.h's
# real MODKEY/col_accent (repo-relative, deterministic) and "no ~/.xinitrc
# wallpaper block" -> wallpaper none (HOME sandboxed to an empty tmp dir).
# Sandbox also strips ly/dwm signals via the override seams so this reports
# a fresh setup deterministically regardless of the host running the suite.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  export HOME=$(mktemp -d)
  LY_CONFIG_OVERRIDE=/nonexistent DWM_CHECK_OVERRIDE=missing detect_existing_setup >/dev/null 2>&1
  echo "modkey=$(state_get dwm/modkey)"
  echo "barcolor=$(state_get dwm/barcolor)"
  echo "wallpaper=$(state_get dwm/wallpaper)"
')
assert_contains "$out" "modkey="
assert_contains "$out" "barcolor=#"
assert_contains "$out" "wallpaper=none"

# detect_existing_setup: existing setup signaled by ~/.xinitrc alone (ly/dwm
# signals forced off via the override seams so this is deterministic).
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  export HOME=$(mktemp -d)
  touch "$HOME/.xinitrc"
  EXISTING_SETUP=0; SETUP_BANNER=""
  LY_CONFIG_OVERRIDE=/nonexistent DWM_CHECK_OVERRIDE=missing detect_existing_setup >/dev/null 2>&1
  echo "existing=$EXISTING_SETUP"
  echo "banner=$SETUP_BANNER"
')
assert_contains "$out" "existing=1"
assert_contains "$out" "banner=existing setup detected"

# detect_existing_setup: fresh setup — empty sandbox HOME (no ~/.xinitrc),
# and dwm/ly signals forced off via the override seams.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  export HOME=$(mktemp -d)
  EXISTING_SETUP=0; SETUP_BANNER=""
  LY_CONFIG_OVERRIDE=/nonexistent DWM_CHECK_OVERRIDE=missing detect_existing_setup >/dev/null 2>&1
  echo "existing=$EXISTING_SETUP"
  echo "banner=$SETUP_BANNER"
')
assert_contains "$out" "existing=0"
assert_contains "$out" "banner=fresh setup"

# reconfigure_read_slstatus parses interface + battery-enabled state out of a
# slstatus config.h-shaped fixture. Isolated from detect_existing_setup / the
# repo's real slstatus/config.h so this is deterministic. Fixture 1: an
# active (uncommented) battery_perc line -> battery=on.
out=$(bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  f=$(mktemp)
  printf "\t{ netspeed_rx,     \" %%s\",                \"wlan0\"   },\n\t{ battery_perc, \"[Bat %%s%%%%] \", \"BAT0\" },\n" > "$f"
  reconfigure_read_slstatus "$f"
  echo "interface=$(state_get dwm/interface)"
  echo "battery=$(state_get dwm/battery)"
  rm -f "$f"
')
assert_contains "$out" "interface=wlan0"
assert_contains "$out" "battery=on"

# Fixture 2: a commented-out (//{) battery_perc line -> battery=off, and a
# different interface value to confirm it is read fresh each call.
out=$(bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  f=$(mktemp)
  printf "\t{ netspeed_rx,     \" %%s\",                \"eth0\"   },\n\t//{ battery_perc, \"[Bat %%s%%%%] \", \"BAT0\" },\n" > "$f"
  reconfigure_read_slstatus "$f"
  echo "interface=$(state_get dwm/interface)"
  echo "battery=$(state_get dwm/battery)"
  rm -f "$f"
')
assert_contains "$out" "interface=eth0"
assert_contains "$out" "battery=off"

# apply_all step gating: --only restricts to matching steps (mocked so this
# is deterministic and side-effect free regardless of DRY_RUN).
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  debloat_apply() { echo "debloat ran"; }
  tweaks_apply() { echo "tweaks ran"; }
  install_selected_packages() { echo "install ran"; }
  build_selected_components_maybe() { echo "build ran"; }
  apply_configuration_maybe() { echo "configure ran"; }
  configure_ly_display_manager_maybe() { echo "ly ran"; }
  wallpaper_apply_maybe() { echo "wallpaper ran"; }
  profile_save() { :; }
  tui_msgbox() { :; }
  ONLY_SECTIONS=(dwm)
  export HOME=$(mktemp -d)
  export XDG_STATE_HOME=$(mktemp -d)
  apply_all
')
assert_contains "$out" "==> Configure"
assert_contains "$out" "==> Wallpaper"
assert_eq "$(echo "$out" | grep -c '==> Debloat')" "0"
assert_eq "$(echo "$out" | grep -c '==> Install packages')" "0"
assert_eq "$(echo "$out" | grep -c '==> Build components')" "0"
assert_eq "$(echo "$out" | grep -c '==> Ly')" "0"

# --skip-packages skips only the "Install packages" step, not "Build
# components" (which is also gated by the "install" section).
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  debloat_apply() { echo "debloat ran"; }
  tweaks_apply() { echo "tweaks ran"; }
  install_selected_packages() { echo "install ran"; }
  build_selected_components_maybe() { echo "build ran"; }
  apply_configuration_maybe() { echo "configure ran"; }
  configure_ly_display_manager_maybe() { echo "ly ran"; }
  wallpaper_apply_maybe() { echo "wallpaper ran"; }
  profile_save() { :; }
  tui_msgbox() { :; }
  SKIP_PACKAGES=1
  export HOME=$(mktemp -d)
  export XDG_STATE_HOME=$(mktemp -d)
  apply_all
')
assert_eq "$(echo "$out" | grep -c '==> Install packages')" "0"
assert_contains "$out" "==> Build components"
assert_contains "$out" "==> Debloat"

# --- Task 10 Step 3 acceptance gate: non-interactive dry-run smoke tests,
# run as real subprocesses of ./manjaro-sl.sh with HOME/XDG_STATE_HOME
# sandboxed to temp dirs (apply_all writes a run log + saved profile there;
# everything mutating goes through run_mut/the DRY_RUN-gated adapters, so
# no real system change happens either way). No sudo prompt, no whiptail.

t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --preset minimal --dry-run --apply 2>&1); rc=$?
assert_eq "$rc" "0"
rns_line=$(echo "$out" | grep 'pacman -Rns' || true)
assert_contains "$rns_line" "+ sudo pacman -Rns"
assert_contains "$out" "+ sudo systemctl enable NetworkManager.service"
# I6: these two assertions are host-coupled — they only hold if
# manjaro-hello is actually installed on the machine running the suite
# (proving the dry run left it untouched). Guard them so the suite still
# passes on a host that's already been debloated.
if pacman -Qi manjaro-hello >/dev/null 2>&1; then
  assert_contains "$rns_line" "manjaro-hello"
  assert_ok bash -c 'pacman -Qi manjaro-hello >/dev/null'
else
  echo "SKIP: manjaro-hello not installed (host already debloated?)"
fi
rm -rf "$t_home" "$t_state"

t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --preset recommended --dry-run --apply 2>&1)
assert_eq "$(echo "$out" | grep -c pamac)" "0"
rm -rf "$t_home" "$t_state"

# Flag order: --disable-manjaro-hello placed AFTER --preset overrides it
# (see the strict left-to-right ordering established above).
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --preset minimal --disable-manjaro-hello --dry-run --apply 2>&1)
rns_line=$(echo "$out" | grep 'Rns' || true)
assert_eq "$(echo "$rns_line" | grep -c manjaro-hello)" "0"
rm -rf "$t_home" "$t_state"

# --- Task 11: legacy positional component args (`./manjaro-sl.sh st`) must
# select just that component instead of hitting parse_args' unknown-option
# error path.

# 1. Legacy per-component invocation, called directly on manjaro-sl.sh with
# --skip-packages (isolates the Build-components note from the
# Install-packages step).
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  st --dry-run --apply --skip-packages 2>&1); rc=$?
assert_eq "$rc" "0"
build_line=$(echo "$out" | grep 'skipping Build components' || true)
assert_contains "$build_line" "selected: st"
assert_eq "$(echo "$build_line" | grep -c 'dwm')" "0"
rm -rf "$t_home" "$t_state"

# xmatrix is a valid positional component (sandboxed HOME/XDG_STATE_HOME, --dry-run)
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  xmatrix --dry-run --apply --skip-packages 2>&1); rc=$?
assert_eq "$rc" "0"
build_line=$(echo "$out" | grep 'skipping Build components' || true)
assert_contains "$build_line" "selected: xmatrix"
rm -rf "$t_home" "$t_state"

# xcolormix is a valid positional component (sandboxed HOME/XDG_STATE_HOME, --dry-run)
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  xcolormix --dry-run --apply --skip-packages 2>&1); rc=$?
assert_eq "$rc" "0"
build_line=$(echo "$out" | grep 'skipping Build components' || true)
assert_contains "$build_line" "selected: xcolormix"
rm -rf "$t_home" "$t_state"

# 2. Unknown positional component name must error out clearly.
out=$(HOME=$(mktemp -d) "$REPO_ROOT/manjaro-sl.sh" notacomponent --dry-run --apply 2>&1); rc=$?
assert_eq "$rc" "1"
assert_contains "$out" "Unknown component"

# 3. Positional component names are applied after --preset, so they
# override the preset's own component selection (consistent with the
# documented left-to-right-then-positionals rule).
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --preset minimal st --dry-run --apply --skip-packages 2>&1); rc=$?
assert_eq "$rc" "0"
build_line=$(echo "$out" | grep 'skipping Build components' || true)
assert_contains "$build_line" "selected: st"
assert_eq "$(echo "$build_line" | grep -c 'dwm')" "0"
rm -rf "$t_home" "$t_state"

# --- Final review regressions -------------------------------------------

# C1: a bare/legacy run with no --preset and no positional component names
# must not leave every component/* unset ("Build components (selected:
# none)") — seed_default_components seeds the legacy DEFAULT_COMPONENTS set
# (dwm dmenu st slstatus — explicitly NOT doomfire, matching old
# build_suckless.sh) whenever selections carry no component/* key at all.
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  -y --dry-run 2>&1); rc=$?
assert_eq "$rc" "0"
build_line=$(echo "$out" | grep 'skipping Build components' || true)
assert_contains "$build_line" "dwm"
assert_contains "$build_line" "dmenu"
assert_contains "$build_line" "st"
assert_contains "$build_line" "slstatus"
assert_eq "$(echo "$build_line" | grep -c 'doomfire')" "0"
rm -rf "$t_home" "$t_state"

# C1 regression (v2 final-review fix wave): `--wallpaper WP -y` must ADD the
# wallpaper component to the default set, not suppress seeding — the
# select_wallpaper chokepoint's implied component/* key must not make
# seed_default_components think the user hand-picked components.
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --wallpaper doomfire -y --dry-run 2>&1); rc=$?
assert_eq "$rc" "0"
build_line=$(echo "$out" | grep 'skipping Build components' || true)
assert_contains "$build_line" "dwm"
assert_contains "$build_line" "slstatus"
assert_contains "$build_line" "doomfire"
rm -rf "$t_home" "$t_state"

# --- N1/N2 follow-up review fixes ----------------------------------------

# N2: a legacy per-component invocation that doesn't include dwm (`st
# -y --dry-run`, forwarded verbatim from build_suckless.sh) must NOT reach
# the Ly step — ly/enable is unset, which apply treats as "enable Ly" (see
# N1 below), so running the step here would flip the system's display
# manager as a side effect of a plain st rebuild. The Ly step only ever
# prints something (its "==> Ly" run_step header, or under --dry-run the
# "[dry-run] skipping Ly" note printed instead of the real step) when it
# actually executes — apply_all's other gated steps that don't run print
# nothing at all — so absence of "==> Ly" is the correct "step did not run"
# assertion (not "no enable text", which would also spuriously pass if the
# step ran but happened not to enable anything).
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  st -y --dry-run 2>&1); rc=$?
assert_eq "$rc" "0"
assert_eq "$(echo "$out" | grep -c '==> Ly')" "0"
rm -rf "$t_home" "$t_state"

# N2 counterpart: a bare/legacy run with no positional component names seeds
# the default component set (dwm dmenu st slstatus — see C1 above), so it
# DOES include dwm and must still reach the Ly step as before.
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  -y --dry-run 2>&1); rc=$?
assert_eq "$rc" "0"
assert_contains "$out" "[dry-run] skipping Ly"
rm -rf "$t_home" "$t_state"

# N1: preview_text must not claim ly/enable is "off" when it was never set —
# apply's actual behavior for unset ly/enable is to enable Ly (legacy
# build_suckless.sh parity; see lib/ly.sh's C2 gate), so the preview should
# say so instead of implying apply will leave Ly disabled.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  preview_text
')
assert_contains "$out" "enable=on (default)"

out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  state_set ly/enable off
  preview_text
')
assert_contains "$out" "enable=off"

# --- v2 Task 1: repo organization ----------------------------------------

# repo org: the legacy wrapper is gone; bug report lives in docs/
assert_fail test -e "$REPO_ROOT/build_suckless.sh"
assert_ok test -f "$REPO_ROOT/docs/bug_report_and_recommendations.md"

# --- v2 Task 5: Desktop Setup + Appearance menus --------------------------

# appearance_menu drives its whole interactive walk off one stdin stream
# (TUI_ACTIVE=0 fallback prompts all `read` from fd 0 in sequence); each
# test below documents the exact keystroke sequence it feeds. The trailing
# tui_menu re-read after the last state-changing pick always hits EOF (no
# more lines in the herestring), which makes `read` fail, `n` come back
# empty, and the fallback tui_menu echo nothing — so the outer `while true`
# loop's `case "" in back|"") return 0` exits the menu for free without an
# explicit "go back" keystroke.

# 1) Unified Animation picker: top menu tag order is
#    animation(1) advanced(2) enable(3) back(4); the Animation radiolist's
#    tag order is doom(1) matrix(2) colormix(3) none(4) custom(5).
#    "1\n2\n" => open Animation, pick "matrix" => ly/animation=matrix,
#    dwm/wallpaper=xmatrix (ly_animation_to_wallpaper mapping),
#    ly/match_wallpaper=on.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  appearance_menu
  echo "anim=$(state_get ly/animation)"
  echo "wp=$(state_get dwm/wallpaper)"
  echo "match=$(state_get ly/match_wallpaper)"
  echo "comp=$(state_get component/xmatrix)"
' <<< "1
2
")
assert_contains "$out" "anim=matrix"
assert_contains "$out" "wp=xmatrix"
assert_contains "$out" "match=on"
# I1: picking a wallpaper here must also flip on its own component/* — see
# select_wallpaper — or apply_all's Build step never builds it and the
# launcher execs a binary that was never built (flagship final-review-v2 bug).
assert_contains "$out" "comp=on"

# 2) Custom animation: same top pick (1=Animation), radiolist pick "5"
#    (custom = last tag), then the tui_input prompt reads the name verbatim.
#    ly/animation stores the name as-is; dwm/wallpaper falls back to "none"
#    since ly_animation_to_wallpaper only recognizes doom/matrix.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  appearance_menu
  echo "anim=$(state_get ly/animation)"
  echo "wp=$(state_get dwm/wallpaper)"
' <<< "1
5
blackhole
")
assert_contains "$out" "anim=blackhole"
assert_contains "$out" "wp=none"

# 3) Advanced: top pick "2" (Advanced); its Ly-animation radiolist uses the
#    same doom/matrix/colormix/none/custom tag order as Animation ("2" =
#    matrix, stored directly into ly/animation with no wallpaper mapping);
#    its desktop-wallpaper radiolist tag order is none(1) doomfire(2)
#    xmatrix(3) ("2" = doomfire, stored directly into dwm/wallpaper). The
#    two keys are set independently and ly/match_wallpaper is forced off.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  appearance_menu
  echo "anim=$(state_get ly/animation)"
  echo "wp=$(state_get dwm/wallpaper)"
  echo "match=$(state_get ly/match_wallpaper)"
  echo "comp=$(state_get component/doomfire)"
' <<< "2
2
2
")
assert_contains "$out" "anim=matrix"
assert_contains "$out" "wp=doomfire"
assert_contains "$out" "match=off"
# I1: the Advanced desktop-wallpaper radiolist is also a select_wallpaper
# chokepoint — same guarantee as the unified picker above.
assert_contains "$out" "comp=on"

# Menu integrity (static source assertions): task-oriented main menu items
# present, legacy per-screen entrances and their tui_menu titles gone.
main_menu_block=$(sed -n '/^main_menu() {/,/^}/p' "$REPO_ROOT/manjaro-sl.sh")
assert_contains "$main_menu_block" 'desktop "Desktop Setup"'
assert_contains "$main_menu_block" 'appearance "Appearance"'
assert_eq "$(echo "$main_menu_block" | grep -o ';;' | wc -l)" "7"   # 7 case arms = 7 menu entries
assert_eq "$(grep -c 'Reconfigure' "$REPO_ROOT/manjaro-sl.sh")" "0"
assert_eq "$(grep -c '"Install DWM' "$REPO_ROOT/manjaro-sl.sh")" "0"
assert_eq "$(grep -c '"Configure DWM' "$REPO_ROOT/manjaro-sl.sh")" "0"
assert_eq "$(grep -c '"Ly Display Manager' "$REPO_ROOT/manjaro-sl.sh")" "0"
assert_eq "$(grep -c '^install_screen()' "$REPO_ROOT/manjaro-sl.sh")" "0"
assert_eq "$(grep -c '^dwm_menu()' "$REPO_ROOT/manjaro-sl.sh")" "0"
assert_eq "$(grep -c '^ly_menu()' "$REPO_ROOT/manjaro-sl.sh")" "0"

# --- Final review v2 fixes -------------------------------------------------

# I1: selecting a wallpaper never selected its own component/* for building
# (flagship bug) — a component that was never built/installed still got
# exec'd by wallpaper.sh's launcher, silently, since the launcher runs
# backgrounded from ~/.xinitrc. select_wallpaper is the fix's single
# chokepoint; the CLI --wallpaper flag is one of its call sites (see also
# the appearance_menu unified/Advanced assertions added above).
t_home=$(mktemp -d); t_state=$(mktemp -d)
out=$(HOME="$t_home" XDG_STATE_HOME="$t_state" "$REPO_ROOT/manjaro-sl.sh" \
  --preset recommended --wallpaper xmatrix --dry-run --apply 2>&1); rc=$?
assert_eq "$rc" "0"
build_line=$(echo "$out" | grep 'skipping Build components' || true)
assert_contains "$build_line" "xmatrix"
rm -rf "$t_home" "$t_state"

# I1: sync_ly_wallpaper (the Preview & Apply parent-shell sync — see its own
# comment) is also a select_wallpaper chokepoint: a match_wallpaper=on
# selection whose ly/animation maps to xmatrix must flip on component/xmatrix
# too, not just dwm/wallpaper.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  state_set ly/match_wallpaper on
  state_set ly/animation matrix
  sync_ly_wallpaper
  echo "wp=$(state_get dwm/wallpaper)"
  echo "comp=$(state_get component/xmatrix)"
')
assert_contains "$out" "wp=xmatrix"
assert_contains "$out" "comp=on"

# M4: the unified Custom… branch used to unconditionally claim "desktop
# wallpaper set to 'none'" even when the typed name happens to match a known
# animation (ly_animation_to_wallpaper recognizes "doom"/"matrix" verbatim).
# Typing "matrix" via Custom… must set dwm/wallpaper=xmatrix, flip on
# component/xmatrix, and say so instead of lying about 'none'.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  appearance_menu
  echo "anim=$(state_get ly/animation)"
  echo "wp=$(state_get dwm/wallpaper)"
  echo "comp=$(state_get component/xmatrix)"
' <<< "1
5
matrix
" 2>&1)
assert_contains "$out" "anim=matrix"
assert_contains "$out" "wp=xmatrix"
assert_contains "$out" "comp=on"
assert_eq "$(echo "$out" | grep -c "desktop wallpaper set to 'none'")" "0"

# I2: detect_existing_setup used to clobber a preloaded/profile-loaded
# wallpaper with a hardcoded "doomfire" guess whenever the ~/.xinitrc
# wallpaper block existed, regardless of which wallpaper was actually wired
# in. The launcher's own `exec WP` line is now authoritative: a generated
# xmatrix launcher + the xinitrc block must read back as xmatrix, not
# doomfire. ly/dwm signals are neutralized via the override seams so this is
# deterministic regardless of the host running the suite.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  export HOME=$(mktemp -d)
  mkdir -p "$HOME/.config/manjaro-sl"
  printf "#!/usr/bin/env bash\nexec xmatrix\n" > "$HOME/.config/manjaro-sl/wallpaper.sh"
  {
    printf "# >>> manjaro-sl wallpaper >>>\n"
    printf "\"\$HOME/.config/manjaro-sl/wallpaper.sh\" &\n"
    printf "# <<< manjaro-sl wallpaper <<<\n"
  } > "$HOME/.xinitrc"
  LY_CONFIG_OVERRIDE=/nonexistent DWM_CHECK_OVERRIDE=missing detect_existing_setup >/dev/null 2>&1
  echo "wallpaper=$(state_get dwm/wallpaper)"
')
assert_contains "$out" "wallpaper=xmatrix"

# I2 counterpart: an xinitrc block with no launcher script at all (pre-
# launcher install, or one that predates wallpaper.sh writing an `exec WP`
# line) must still fall back to the old "doomfire" guess rather than picking
# up nothing/erroring.
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  export HOME=$(mktemp -d)
  {
    printf "# >>> manjaro-sl wallpaper >>>\n"
    printf "\"\$HOME/.config/manjaro-sl/wallpaper.sh\" &\n"
    printf "# <<< manjaro-sl wallpaper <<<\n"
  } > "$HOME/.xinitrc"
  LY_CONFIG_OVERRIDE=/nonexistent DWM_CHECK_OVERRIDE=missing detect_existing_setup >/dev/null 2>&1
  echo "wallpaper=$(state_get dwm/wallpaper)"
')
assert_contains "$out" "wallpaper=doomfire"

# I3/M2/M6: doc/comment accuracy — no more stale ly_menu references, and
# "phase 2" -> "phase 3" wording lines up with the README/design spec.
assert_eq "$(grep -c 'ly_menu' "$REPO_ROOT/lib/ly.sh")" "0"
assert_eq "$(grep -c 'phase 2\|phase-2' "$REPO_ROOT/lib/ly.sh")" "0"
assert_eq "$(grep -c 'phase 2\|phase-2' "$REPO_ROOT/lib/wallpaper.sh")" "0"
assert_contains "$(cat "$REPO_ROOT/readme.md")" "runs once per launch, but only on the interactive path"
assert_eq "$(grep -c 'before flags override anything' "$REPO_ROOT/readme.md")" "0"
