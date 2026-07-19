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
out=$(env -i PATH="$nosudo_dir" HOME="$HOME" bash "$REPO_ROOT/build_suckless.sh" --help 2>&1); rc=$?
assert_eq "$rc" "0"
assert_contains "$out" "Usage:"

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
assert_eq "$(ly_animation_to_wallpaper matrix)" "none"

HOME=$OLD_HOME

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

unset -f pacman systemctl run_with_privilege require_command
