# manjaro-sl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `sl` repo into `manjaro-sl` — a whiptail-TUI Manjaro debloater + DWM setup tool with a from-scratch Doom-fire X11 wallpaper, per the spec at `docs/superpowers/specs/2026-07-18-manjaro-sl-design.md`.

**Architecture:** Thin entry script (`manjaro-sl.sh`) sources modules from `lib/`; package/category lists live in `data/` and generate the TUI screens; all mutations funnel through a dry-run-able `run_mut` helper and a `run_step` harness. `doomfire/` is a standalone suckless-style C program (libX11 only).

**Tech Stack:** bash 5, whiptail (libnewt), pacman, systemd, python3 (existing config editors), C99 + libX11 (doomfire).

## Global Constraints

- Target: Arch-based distros with pacman; primary target Manjaro. Bash (not POSIX sh) — shebang `#!/usr/bin/env bash`, `set -euo pipefail` everywhere.
- Never run `pacman -Rdd`. Removal engine must check the hardcoded denylist before every batch (spec section "Hardcoded denylist").
- Never stop the running display manager — disable only (existing safety dance).
- All mutating commands (pacman/systemctl/install/cp/mkdir on system paths) must go through `run_mut` so `--dry-run` prints instead of executes.
- Existing logic in `build_suckless.sh` is MOVED, not rewritten — function names preserved.
- doomfire links only against libX11. Suckless conventions: `config.def.h`, `config.mk`, MIT LICENSE.
- Logs: `~/.local/state/manjaro-sl/` ; user config/profile: `~/.config/manjaro-sl/`.
- Every task ends with `bash -n` on all changed shell files + `shellcheck` clean (or documented directive) + commit.

## File Structure (final)

```
manjaro-sl.sh                 entry point (arg parse, sanity checks, main menu loop)
build_suckless.sh             deprecated wrapper (replaced at Task 12)
lib/tui.sh                    whiptail wrappers + prompt fallbacks
lib/state.sh                  SELECTIONS array, list parsing, denylist, profile save/load
lib/exec.sh                   run_mut, run_step, logging, DRY_RUN
lib/packages.sh               moved: multilib + package-install engine
lib/suckless.sh               moved: clean/build/install components + j4
lib/configure.sh              moved: config.h editors (modkey/color/iface/battery)
lib/ly.sh                     moved: Ly unit detection/config + match-wallpaper hook
lib/debloat.sh                new: category screens + removal engine (uses moved DE/DM detection)
lib/tweaks.sh                 new: systemd service toggles
lib/wallpaper.sh              new: launcher generation + xinitrc wiring
data/*.list                   package/category data (Task 2)
doomfire/{main.c,config.def.h,config.mk,Makefile,LICENSE}
tests/run-tests.sh            self-contained assertion runner (no bats)
tests/lib-tests.sh            unit tests for state/denylist/list parsing
docs/…                        spec (done) + this plan
```

---

### Task 1: Scaffold — exec engine, test runner, entry skeleton

**Files:**
- Create: `lib/exec.sh`, `tests/run-tests.sh`, `tests/lib-tests.sh`, `manjaro-sl.sh`

**Interfaces:**
- Produces: `run_mut CMD...` (echoes `+ CMD` when `DRY_RUN=1`, else runs via `run_with_privilege` when first arg is `sudo:`-prefixed), `run_step "Title" fn` (tees to log, failure menu), `log_dir` (echoes `~/.local/state/manjaro-sl`, creates it), `DRY_RUN` global (0/1). Test helpers: `assert_eq`, `assert_contains`, `assert_ok`, `assert_fail`.

- [ ] **Step 1: Write failing test file**

`tests/run-tests.sh`:
```bash
#!/usr/bin/env bash
# Minimal test runner: sources every tests/*-tests.sh and reports.
set -uo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$TESTS_DIR")
PASS=0; FAIL=0; CURRENT=""

assert_eq()       { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL($CURRENT): expected [$2] got [$1]"; fi; }
assert_contains() { if [[ "$1" == *"$2"* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL($CURRENT): [$1] lacks [$2]"; fi; }
assert_ok()       { if "$@"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL($CURRENT): $* returned nonzero"; fi; }
assert_fail()     { if "$@"; then FAIL=$((FAIL+1)); echo "FAIL($CURRENT): $* unexpectedly succeeded"; else PASS=$((PASS+1)); fi; }

for f in "$TESTS_DIR"/*-tests.sh; do
  CURRENT=$(basename "$f")
  # shellcheck source=/dev/null
  source "$f"
done
echo "----"; echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
```

`tests/lib-tests.sh` (first assertions):
```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run-tests.sh`
Expected: FAIL — `lib/exec.sh: No such file or directory`

- [ ] **Step 3: Implement `lib/exec.sh`**

```bash
#!/usr/bin/env bash
# Mutation gate, step harness, and logging for manjaro-sl.
# Every command that changes system state goes through run_mut so that
# --dry-run can print instead of execute.

DRY_RUN=${DRY_RUN:-0}

log_dir() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/manjaro-sl"
  mkdir -p "$d"
  echo "$d"
}

# run_mut CMD ARGS...
# Prefix "sudo:" as $1 to request privilege (uses run_with_privilege if the
# caller has defined it, else sudo).
run_mut() {
  local priv=0
  if [ "${1:-}" = "sudo:" ]; then priv=1; shift; fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$priv" -eq 1 ]; then echo "+ sudo $*"; else echo "+ $*"; fi
    return 0
  fi
  if [ "$priv" -eq 1 ]; then
    if declare -F run_with_privilege >/dev/null; then
      run_with_privilege "$@"
    else
      sudo "$@"
    fi
  else
    "$@"
  fi
}

# run_step "Title" fn — run fn, tee output to the run log; on failure offer
# View log / Continue / Abort (falls back to plain prompt without whiptail).
RUN_LOG=""
run_step() {
  local title="$1" fn="$2"
  if [ -z "$RUN_LOG" ]; then
    RUN_LOG="$(log_dir)/run-$(date +%Y%m%d%H%M%S).log"
  fi
  echo "==> ${title}" | tee -a "$RUN_LOG"
  if "$fn" 2>&1 | tee -a "$RUN_LOG"; then
    return 0
  fi
  local rc=$?
  echo "Step '${title}' failed (exit $rc). Log: $RUN_LOG" >&2
  if declare -F tui_yesno >/dev/null && [ "${TUI_ACTIVE:-0}" -eq 1 ]; then
    if tui_yesno "Step failed" "Step '${title}' failed.\nLog: ${RUN_LOG}\n\nContinue with remaining steps?"; then
      return 0
    fi
    return "$rc"
  fi
  local ans
  read -r -p "Continue with remaining steps? [y/N] " ans || ans=""
  [[ "$ans" =~ ^[Yy] ]] && return 0
  return "$rc"
}
```

- [ ] **Step 4: Create `manjaro-sl.sh` skeleton** (grows in later tasks)

```bash
#!/usr/bin/env bash
# manjaro-sl — Manjaro debloater + DWM/suckless setup TUI.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for m in exec tui state; do
  [ -f "$REPO_ROOT/lib/$m.sh" ] && source "$REPO_ROOT/lib/$m.sh"
done

main() {
  echo "manjaro-sl: scaffold (menus arrive in later tasks)"
}
main "$@"
```

- [ ] **Step 5: Verify pass + lint + commit**

Run: `bash tests/run-tests.sh` → `PASS: 5  FAIL: 0` (exact count may grow)
Run: `bash -n manjaro-sl.sh lib/exec.sh && shellcheck -x manjaro-sl.sh lib/exec.sh tests/*.sh` → clean
```bash
git add lib/exec.sh tests/ manjaro-sl.sh
git commit -m "feat: manjaro-sl scaffold with run_mut/run_step exec engine and test runner"
```

---

### Task 2: Data files + state engine (lists, denylist, profiles)

**Files:**
- Create: `data/install-core.list`, `data/install-recommended.list`, `data/debloat-manjaro.list`, `data/debloat-apps.list`, `data/debloat-printing.list`, `data/debloat-bluetooth.list`, `data/tweaks-services.list`, `data/dm.list`, `data/de.list`, `lib/state.sh`
- Modify: `tests/lib-tests.sh` (append)

**Interfaces:**
- Produces: `SELECTIONS` (global assoc array, key=`category/name`, value=`on|off`), `state_set KEY VAL`, `state_get KEY` (echoes value or "off"), `state_on KEY` (exit 0 if on), `list_entries FILE` (echoes `name|desc|state` lines, comments stripped), `denylisted PKG` (exit 0 if pkg matches denylist), `profile_save FILE` / `profile_load FILE`.

- [ ] **Step 1: Write the data files** (content is normative — from spec)

`data/install-core.list`:
```
# Always installed. Not shown as options.
base-devel|Compiler toolchain|on
libx11|X11 client library|on
libxft|X FreeType interface|on
libxinerama|Multi-monitor support|on
freetype2|Font rendering|on
fontconfig|Font configuration|on
pkgconf|Build configuration|on
python|Used by config editors|on
libnewt|whiptail TUI|on
xorg|X.Org display server (group)|on
xorg-xinit|startx / xinit|on
ly|TUI display manager|on
```

`data/install-recommended.list`:
```
feh|Image viewer / wallpaper setter|on
meson|Build system (j4-dmenu-desktop)|on
fastfetch|System info|on
htop|Process viewer|on
nano|Text editor|on
networkmanager|Network management|on
network-manager-applet|Tray applet|on
tldr|Simplified man pages|on
brightnessctl|Backlight control|on
alsa-utils|Audio mixer/controls|on
firefox|Web browser|on
net-tools|ifconfig etc.|on
```

`data/debloat-manjaro.list`:
```
manjaro-hello|Welcome app|on
manjaro-application-utility|App installer UI|on
manjaro-settings-manager|Settings GUI|on
manjaro-settings-manager-notifier|Settings notifier|on
manjaro-browser-settings|Browser branding|on
manjaro-documentation-en|Offline docs|on
pamac-gtk|Pamac GUI (legacy name)|off
pamac-gtk3|Pamac GUI|off
pamac-cli|Pamac CLI|off
pamac-tray-icon-plasma|Pamac tray (Plasma)|off
libpamac|Pamac library|off
libpamac-flatpak-plugin|Pamac flatpak plugin|off
manjaro-wallpapers-18.0|Stock wallpapers (cosmetic)|off
manjaro-icons|Stock icons (cosmetic)|off
grub-theme-manjaro|Boot theme (cosmetic)|off
manjaro-zsh-config|WARNING: your zsh/powerlevel10k setup|off
```

`data/debloat-apps.list`:
```
thunderbird|Email client|off
hexchat|IRC client|off
pidgin|Messenger|off
gimp|Image editor|off
inkscape|Vector editor|off
libreoffice-still|Office suite (stable)|off
libreoffice-fresh|Office suite (fresh)|off
onlyoffice-desktopeditors|Office suite|off
steam|Game store|off
steam-devices|Steam udev rules|off
lollypop|Music player (GNOME)|off
totem|Video player (GNOME)|off
celluloid|Video player|off
gnome-maps|Maps (GNOME)|off
cheese|Webcam app (GNOME)|off
kget|Download manager (KDE)|off
konversation|IRC client (KDE)|off
parole|Media player (XFCE)|off
timeshift|WARNING: your backup system|off
timeshift-autosnap-manjaro|WARNING: auto-snapshots before upgrades|off
```

`data/debloat-printing.list`:
```
cups|Print server|off
cups-pdf|Print-to-PDF|off
cups-filters|Print filters|off
hplip|HP printer drivers|off
system-config-printer|Printer settings GUI|off
simple-scan|Scanner app|off
sane|Scanner backend|off
print-manager|Print manager (KDE)|off
manjaro-printer|Manjaro printing meta|off
```

`data/debloat-bluetooth.list`:
```
bluez|Bluetooth stack|off
bluez-utils|Bluetooth CLI tools|off
blueman|Bluetooth manager (GTK)|off
bluedevil|Bluetooth (KDE)|off
pulseaudio-bluetooth|PA Bluetooth module|off
blueberry|Bluetooth (Cinnamon)|off
```

`data/tweaks-services.list` (format: `action:unit|desc|state`):
```
enable:NetworkManager.service|Network management on boot|on
enable:fstrim.timer|Weekly SSD TRIM|on
disable:cups.service|Stop print server autostart|off
disable:bluetooth.service|Stop bluetooth autostart|off
enable:ufw.service|Firewall (default deny)|off
```

`data/dm.list` and `data/de.list`: copy the entries of `KNOWN_DISPLAY_MANAGERS` and `KNOWN_DESKTOP_ENVIRONMENTS` arrays from `build_suckless.sh` verbatim, one per line with `|desc|off` (desc = the package name again is fine).

- [ ] **Step 2: Append failing tests to `tests/lib-tests.sh`**

```bash
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
```

- [ ] **Step 3: Run to verify failure** — `bash tests/run-tests.sh` → FAIL (`lib/state.sh` missing)

- [ ] **Step 4: Implement `lib/state.sh`**

```bash
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
```

- [ ] **Step 5: Verify pass + lint + commit**

Run: `bash tests/run-tests.sh` → all PASS; `shellcheck -x lib/state.sh` clean.
```bash
git add data/ lib/state.sh tests/lib-tests.sh
git commit -m "feat: data-file package lists, selection state, denylist, profiles"
```

---

### Task 3: TUI library (whiptail wrappers + fallback)

**Files:**
- Create: `lib/tui.sh`
- Modify: `tests/lib-tests.sh` (append)

**Interfaces:**
- Produces: `tui_available`, `TUI_ACTIVE` (0/1), `tui_menu TITLE PROMPT tag1 item1 tag2 item2...` → echoes chosen tag, `tui_checklist TITLE PROMPT tag item state...` → echoes chosen tags (space-separated, unquoted), `tui_radiolist` (same shape, one tag), `tui_yesno TITLE TEXT`, `tui_msgbox TITLE TEXT`, `tui_input TITLE PROMPT DEFAULT` → echoes value. All fall back to numbered read-based prompts when whiptail is absent or `TUI_ACTIVE=0`.

- [ ] **Step 1: Append tests (fallback paths are testable non-interactively via herestrings)**

```bash
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
```

- [ ] **Step 2: Run to verify failure** — `bash tests/run-tests.sh` → FAIL

- [ ] **Step 3: Implement `lib/tui.sh`**

```bash
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
    printf '\n== %s ==\n%b\n' "$title" "$text"
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
  printf '\n== %s ==\n' "$title"
  local i; for i in "${!tags[@]}"; do printf '%2d) %s\n' "$((i+1))" "${items[$i]}"; done
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
  printf '\n== %s ==\n' "$title"
  local i; for i in "${!tags[@]}"; do
    printf '%2d) [%s] %s\n' "$((i+1))" "$([ "${states[$i]}" = on ] && echo x || echo ' ')" "${items[$i]}"
  done
  local line; read -r -p "$prompt (numbers to toggle, empty=keep): " line || line=""
  local n; for n in $line; do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    i=$((n-1)); [ "$i" -ge 0 ] && [ "$i" -lt "${#tags[@]}" ] || continue
    [ "${states[$i]}" = on ] && states[$i]=off || states[$i]=on
  done
  for i in "${!tags[@]}"; do [ "${states[$i]}" = on ] && printf '%s ' "${tags[$i]}"; done
  echo
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
  printf '\n== %s ==\n' "$title"
  for i in "${!tags[@]}"; do
    printf '%2d) (%s) %s\n' "$((i+1))" "$([ "${states[$i]}" = on ] && echo '*' || echo ' ')" "${items[$i]}"
  done
  local n; read -r -p "$prompt (number, empty=keep): " n || n=""
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#tags[@]}" ]; then
    echo "${tags[$((n-1))]}"
  else
    echo "$def"
  fi
}
```

- [ ] **Step 4: Verify pass + lint + commit**

Run: `bash tests/run-tests.sh` → all PASS; `shellcheck -x lib/tui.sh` clean.
```bash
git add lib/tui.sh tests/lib-tests.sh
git commit -m "feat: whiptail TUI library with non-interactive fallbacks"
```

---

### Task 4: Modularize existing logic (pure moves, no behavior change)

**Files:**
- Create: `lib/packages.sh`, `lib/suckless.sh`, `lib/configure.sh`, `lib/ly.sh`, `lib/common.sh`
- Modify: `build_suckless.sh` (delete moved code, add `source` lines)

**Move map** (cut each function from `build_suckless.sh` verbatim; grep by name):

| Destination | Functions / arrays |
|---|---|
| `lib/common.sh` | `run_with_privilege`, `prompt_yes_no`, `require_command`, `copy_with_backup`, sudo-warning block, `SUDO_CMD` setup |
| `lib/packages.sh` | `ensure_multilib_repo_enabled`, `ensure_recommended_packages`, `RECOMMENDED_PACKAGES`, `BUILD_PACKAGES` |
| `lib/suckless.sh` | `clean_build_artifacts`, `build_j4_with_meson`, `build_j4_with_cmake`, `build_j4_dmenu_desktop`, `component_selected`, the component build loop (wrap in a function `build_components`) |
| `lib/configure.sh` | `configure_slstatus_interface`, `configure_slstatus_battery`, `configure_dwm_bar_color`, `configure_dwm_modkey`, `setup_misc_files` |
| `lib/ly.sh` | `configure_ly_display_manager`, `KNOWN_DISPLAY_MANAGERS` (also read by debloat), `KNOWN_DESKTOP_ENVIRONMENTS`, `detect_and_remove_old_de` |

- [ ] **Step 1:** Create the five lib files, each starting `#!/usr/bin/env bash` + a one-line comment, then move the functions per the map. Do not edit function bodies except: in `lib/suckless.sh`, wrap the trailing top-level component loop of `build_suckless.sh` in `build_components() { ... }`.
- [ ] **Step 2:** In `build_suckless.sh`, replace the moved code with, directly after `REPO_ROOT=...`:

```bash
for m in common packages suckless configure ly; do
  source "$REPO_ROOT/lib/$m.sh"
done
```

and at the old loop's position call `build_components`.

- [ ] **Step 3: Behavior check** — the old entry must still work end-to-end in dry style:

Run: `bash -n build_suckless.sh lib/*.sh` → clean
Run: `./build_suckless.sh --help` → prints usage, exit 0
Run: `./build_suckless.sh --skip-packages --no-remove-de --no-copy-xinit --no-copy-desktop -y st` → builds st exactly as before (this is the regression test; run on this machine).

- [ ] **Step 4:** `shellcheck -x build_suckless.sh lib/*.sh` → clean (add targeted `# shellcheck disable` only where the pre-existing code requires it).

- [ ] **Step 5: Commit**
```bash
git add lib/ build_suckless.sh
git commit -m "refactor: split build_suckless.sh into lib/ modules (pure moves)"
```

---

### Task 5: Debloat engine

**Files:**
- Create: `lib/debloat.sh`
- Modify: `tests/lib-tests.sh` (append)

**Interfaces:**
- Consumes: `list_entries`, `denylisted`, `state_*` (Task 2), `tui_checklist` (Task 3), `run_mut` (Task 1), `KNOWN_DISPLAY_MANAGERS` (Task 4).
- Produces: `debloat_installed_from FILE` → echoes `name|desc|state` for installed packages only; `debloat_screen CATEGORY FILE` → TUI checklist storing to `SELECTIONS[debloat/<name>]`; `debloat_collect` → echoes all selected package names; `debloat_apply` → denylist-checks, disables DM services (never stops), removes via `run_mut sudo: pacman -Rns`, logs to `removed-<ts>.log`.

- [ ] **Step 1: Append tests**

```bash
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
```

- [ ] **Step 2: Run to verify failure** — FAIL (`lib/debloat.sh` missing)

- [ ] **Step 3: Implement `lib/debloat.sh`**

```bash
#!/usr/bin/env bash
# Debloat engine: category screens generated from data files, removal with
# denylist enforcement, DM-safe disabling, and removal logging.

# Echo entries from FILE whose package is currently installed.
debloat_installed_from() {
  local line name
  while IFS= read -r line; do
    name=${line%%|*}
    if pacman -Qq "$name" >/dev/null 2>&1; then
      echo "$line"
    fi
  done < <(list_entries "$1")
}

# Show a checklist for CATEGORY from FILE; store results in SELECTIONS.
debloat_screen() {
  local category="$1" file="$2"
  local -a args=()
  local line name desc state cur
  while IFS='|' read -r name desc state; do
    cur=$(state_get "debloat/$name")
    # SELECTIONS wins over file default once user has visited any screen
    [ -n "${SELECTIONS[debloat/$name]:-}" ] && state="$cur"
    args+=("$name" "$desc" "$state")
  done < <(debloat_installed_from "$file")
  if [ ${#args[@]} -eq 0 ]; then
    tui_msgbox "$category" "Nothing from this category is installed."
    return 0
  fi
  local chosen; chosen=$(tui_checklist "$category" "Space toggles, Enter confirms" "${args[@]}") || return 0
  # reset every entry in this file to off, then re-mark chosen
  while IFS='|' read -r name desc state; do state_set "debloat/$name" off; done \
    < <(debloat_installed_from "$file")
  local tag; for tag in $chosen; do state_set "debloat/$tag" on; done
}

debloat_collect() {
  local key
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == debloat/* ]] && [ "${SELECTIONS[$key]}" = on ] && echo "${key#debloat/}"
  done
}

debloat_apply() {
  local -a to_remove=()
  local pkg
  while IFS= read -r pkg; do
    if denylisted "$pkg"; then
      echo "REFUSED (denylist): $pkg"
      continue
    fi
    to_remove+=("$pkg")
  done < <(debloat_collect | sort)
  [ ${#to_remove[@]} -eq 0 ] && { echo "Nothing selected for removal."; return 0; }

  # Disable (never stop) any DM being removed — black-screen safety.
  local dm
  for dm in "${KNOWN_DISPLAY_MANAGERS[@]:-}"; do
    for pkg in "${to_remove[@]}"; do
      if [ "$pkg" = "$dm" ]; then
        echo "Disabling ${dm}.service (takes effect next boot)"
        run_mut sudo: systemctl disable "${dm}.service" || true
      fi
    done
  done

  local logf; logf="$(log_dir)/removed-$(date +%Y%m%d%H%M%S).log"
  if [ "$DRY_RUN" -eq 0 ]; then
    pacman -Q "${to_remove[@]}" > "$logf" 2>/dev/null || true
    echo "Removal list logged to $logf"
  fi
  run_mut sudo: pacman -Rns "${to_remove[@]}"
}
```

- [ ] **Step 4: Verify pass + lint + commit**

Run: `bash tests/run-tests.sh` → PASS; `shellcheck -x lib/debloat.sh` clean.
```bash
git add lib/debloat.sh tests/lib-tests.sh
git commit -m "feat: debloat engine with denylist, DM-safe disable, removal logging"
```

---

### Task 6: Tweaks engine

**Files:**
- Create: `lib/tweaks.sh`
- Modify: `tests/lib-tests.sh` (append)

**Interfaces:**
- Produces: `tweaks_screen` (checklist from `data/tweaks-services.list`, stores `SELECTIONS[tweak/<action>:<unit>]`), `tweaks_apply` (runs `run_mut sudo: systemctl enable|disable UNIT`; for `enable:ufw.service` additionally `run_mut sudo: ufw default deny incoming` + `run_mut sudo: ufw enable`).

- [ ] **Step 1: Append tests**

```bash
source "$REPO_ROOT/lib/tweaks.sh"
declare -gA SELECTIONS=()
state_set "tweak/enable:fstrim.timer" on
state_set "tweak/disable:cups.service" on
DRY_RUN=1
out=$(tweaks_apply)
assert_contains "$out" "+ sudo systemctl enable fstrim.timer"
assert_contains "$out" "+ sudo systemctl disable cups.service"
```

- [ ] **Step 2:** Run → FAIL. **Step 3: Implement**

```bash
#!/usr/bin/env bash
# System tweaks: systemd unit enable/disable driven by data/tweaks-services.list.

tweaks_screen() {
  local -a args=()
  local action_unit desc state cur
  while IFS='|' read -r action_unit desc state; do
    cur=$(state_get "tweak/$action_unit")
    [ -n "${SELECTIONS[tweak/$action_unit]:-}" ] && state="$cur"
    args+=("$action_unit" "$desc" "$state")
  done < <(list_entries "$REPO_ROOT/data/tweaks-services.list")
  local chosen; chosen=$(tui_checklist "System Tweaks" "Space toggles, Enter confirms" "${args[@]}") || return 0
  while IFS='|' read -r action_unit desc state; do
    state_set "tweak/$action_unit" off
  done < <(list_entries "$REPO_ROOT/data/tweaks-services.list")
  local tag; for tag in $chosen; do state_set "tweak/$tag" on; done
}

tweaks_apply() {
  local key action unit
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == tweak/* ]] && [ "${SELECTIONS[$key]}" = on ] || continue
    action=${key#tweak/}; unit=${action#*:}; action=${action%%:*}
    if [ "$action" = "enable" ] && [ "$unit" = "ufw.service" ]; then
      run_mut sudo: ufw default deny incoming
      run_mut sudo: ufw enable
    fi
    run_mut sudo: systemctl "$action" "$unit"
  done
}
```

- [ ] **Step 4:** tests PASS, shellcheck clean, commit `feat: system tweaks engine`.

---

### Task 7: doomfire (from-scratch Doom fire X11 wallpaper)

**Files:**
- Create: `doomfire/main.c`, `doomfire/config.def.h`, `doomfire/config.mk`, `doomfire/Makefile`, `doomfire/LICENSE` (MIT, your name)

**Interfaces:**
- Produces: `doomfire` binary — paints animated PSX Doom fire on the X11 root window at `FPS` frames/sec until killed. Installs to `/usr/local/bin/doomfire`. Later tasks invoke it by name from the wallpaper launcher.

- [ ] **Step 1: `doomfire/config.def.h`**

```c
/* doomfire configuration — copy to config.h and edit, suckless-style */

/* frames per second (CPU cost scales roughly linearly) */
static const int FPS = 24;

/* fire simulation buffer size; scaled to the screen with nearest-neighbor.
 * Smaller = chunkier pixels + less CPU. Classic PSX look: 320x168. */
static const int FIRE_W = 320;
static const int FIRE_H = 168;
```

- [ ] **Step 2: `doomfire/main.c`** (complete)

```c
/* doomfire — PSX Doom fire on the X11 root window.
 * Algorithm: Fabien Sanglard's "How Doom fire was done" (public domain).
 * Links against libX11 only. MIT licensed. */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "config.h"

static const uint8_t palette[37][3] = {
    {0x07,0x07,0x07},{0x1F,0x07,0x07},{0x2F,0x0F,0x07},{0x47,0x0F,0x07},
    {0x57,0x17,0x07},{0x67,0x1F,0x07},{0x77,0x1F,0x07},{0x8F,0x27,0x07},
    {0x9F,0x2F,0x07},{0xAF,0x3F,0x07},{0xBF,0x47,0x07},{0xC7,0x47,0x07},
    {0xDF,0x4F,0x07},{0xDF,0x57,0x07},{0xDF,0x57,0x07},{0xD7,0x5F,0x07},
    {0xD7,0x5F,0x07},{0xD7,0x67,0x0F},{0xCF,0x6F,0x0F},{0xCF,0x77,0x0F},
    {0xCF,0x7F,0x0F},{0xCF,0x87,0x17},{0xC7,0x87,0x17},{0xC7,0x8F,0x17},
    {0xC7,0x97,0x1F},{0xBF,0x9F,0x1F},{0xBF,0x9F,0x1F},{0xBF,0xA7,0x27},
    {0xBF,0xA7,0x27},{0xBF,0xAF,0x2F},{0xB7,0xAF,0x2F},{0xB7,0xB7,0x2F},
    {0xB7,0xB7,0x37},{0xCF,0xCF,0x6F},{0xDF,0xDF,0x9F},{0xEF,0xEF,0xC7},
    {0xFF,0xFF,0xFF},
};

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static void spread(uint8_t *fire) {
    for (int y = 1; y < FIRE_H; y++) {
        for (int x = 0; x < FIRE_W; x++) {
            int src = y * FIRE_W + x;
            uint8_t p = fire[src];
            if (p == 0) {
                fire[src - FIRE_W] = 0;
            } else {
                int rnd = rand() & 3;
                int dst = src - rnd + 1;
                if (dst < FIRE_W) dst = src;      /* clamp row underflow */
                fire[dst - FIRE_W] = (uint8_t)(p - (rnd & 1));
            }
        }
    }
}

int main(int argc, char *argv[]) {
    int frames = -1;                    /* -1 = run forever */
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);         /* -n N: render N frames and exit (tests) */

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "doomfire: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    int depth = DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, (unsigned)depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    char *data = calloc((size_t)sw * sh, 4);
    if (!data) { fprintf(stderr, "doomfire: oom\n"); return 1; }
    XImage *img = XCreateImage(dpy, DefaultVisual(dpy, scr), (unsigned)depth,
                               ZPixmap, 0, data, (unsigned)sw, (unsigned)sh, 32, 0);

    uint8_t *fire = calloc((size_t)FIRE_W * FIRE_H, 1);
    if (!fire) { fprintf(stderr, "doomfire: oom\n"); return 1; }
    for (int x = 0; x < FIRE_W; x++)
        fire[(FIRE_H - 1) * FIRE_W + x] = 36;   /* white-hot bottom row */

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);

    struct timespec tick = {0, 1000000000L / FPS};
    srand((unsigned)time(NULL));

    while (running && frames != 0) {
        spread(fire);
        /* nearest-neighbor scale fire buffer to screen-size XImage */
        for (int y = 0; y < sh; y++) {
            int fy = y * FIRE_H / sh;
            for (int x = 0; x < sw; x++) {
                int fx = x * FIRE_W / sw;
                const uint8_t *c = palette[fire[fy * FIRE_W + fx]];
                XPutPixel(img, x, y,
                          ((unsigned long)c[0] << 16) |
                          ((unsigned long)c[1] << 8) | c[2]);
            }
        }
        XPutImage(dpy, pm, gc, img, 0, 0, 0, 0, (unsigned)sw, (unsigned)sh);
        XChangeProperty(dpy, root, prop_root, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XChangeProperty(dpy, root, prop_eset, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XSetWindowBackgroundPixmap(dpy, root, pm);
        XClearWindow(dpy, root);
        XFlush(dpy);
        if (frames > 0) frames--;
        nanosleep(&tick, NULL);
    }

    XDestroyImage(img);                 /* frees data */
    free(fire);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3: `doomfire/config.mk` + `doomfire/Makefile`** (match the style of `dwm/config.mk`)

`config.mk`:
```make
VERSION = 0.1
PREFIX = /usr/local
X11INC = /usr/include/X11
X11LIB = /usr/lib/X11
INCS = -I${X11INC}
LIBS = -L${X11LIB} -lX11
CPPFLAGS = -DVERSION=\"${VERSION}\"
CFLAGS = -std=c99 -pedantic -Wall -Wextra -Os ${INCS} ${CPPFLAGS}
CC = cc
```

`Makefile`:
```make
include config.mk

all: doomfire

config.h:
	cp config.def.h $@

doomfire: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f doomfire

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f doomfire ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/doomfire

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/doomfire

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./doomfire -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
```

- [ ] **Step 4: Build + test**

Run: `make -C doomfire` → compiles warning-free.
Run: `make -C doomfire test` → exit 0 (renders 10 frames on Xvfb, or clean skip if Xvfb absent).

- [ ] **Step 5: Commit**
```bash
git add doomfire/
git commit -m "feat: doomfire — from-scratch PSX Doom fire X11 root-window wallpaper"
```

---

### Task 8: Wallpaper wiring

**Files:**
- Create: `lib/wallpaper.sh`
- Modify: `tests/lib-tests.sh` (append), `lib/suckless.sh` (add `doomfire` to buildable components list), `lib/ly.sh` (match-wallpaper hook)

**Interfaces:**
- Consumes: `state_get dwm/wallpaper` (`none|doomfire`), `state_get ly/animation`, `run_mut`.
- Produces: `wallpaper_write_launcher` (writes `~/.config/manjaro-sl/wallpaper.sh`), `wallpaper_wire_xinitrc` (idempotently manages a marked block in `~/.xinitrc`), `wallpaper_apply` (both, or removes block when `none`), `ly_animation_to_wallpaper ANIM` → echoes matching wallpaper (`doom→doomfire`, else `none`).

- [ ] **Step 1: Append tests**

```bash
source "$REPO_ROOT/lib/wallpaper.sh"
declare -gA SELECTIONS=()
DRY_RUN=0
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

assert_eq "$(ly_animation_to_wallpaper doom)" "doomfire"
assert_eq "$(ly_animation_to_wallpaper matrix)" "none"
```

(Reset `HOME` after this block: capture `OLD_HOME=$HOME` before, restore after.)

- [ ] **Step 2:** Run → FAIL. **Step 3: Implement `lib/wallpaper.sh`**

```bash
#!/usr/bin/env bash
# Wallpaper subsystem: writes the launcher script and wires it into ~/.xinitrc
# inside a marked, idempotent block.

WP_BLOCK_START="# >>> manjaro-sl wallpaper >>>"
WP_BLOCK_END="# <<< manjaro-sl wallpaper <<<"

ly_animation_to_wallpaper() {
  case "$1" in
    doom) echo doomfire ;;
    *)    echo none ;;   # matrix/colormix are phase 2
  esac
}

wallpaper_write_launcher() {
  local wp="$1" dir="$HOME/.config/manjaro-sl" f
  f="$dir/wallpaper.sh"
  mkdir -p "$dir"
  cat > "$f" <<EOF
#!/usr/bin/env bash
# Generated by manjaro-sl — starts the desktop wallpaper animation.
exec $wp
EOF
  chmod 755 "$f"
}

wallpaper_strip_block() {
  local xi="$HOME/.xinitrc"
  [ -f "$xi" ] || return 0
  sed -i "\|^${WP_BLOCK_START}\$|,\|^${WP_BLOCK_END}\$|d" "$xi"
}

wallpaper_wire_xinitrc() {
  local xi="$HOME/.xinitrc"
  wallpaper_strip_block
  touch "$xi"
  # Insert before an 'exec dwm' line if present, else append.
  local block
  block=$(printf '%s\n%s\n%s' "$WP_BLOCK_START" \
    "\"\$HOME/.config/manjaro-sl/wallpaper.sh\" &" "$WP_BLOCK_END")
  if grep -q '^exec .*dwm' "$xi"; then
    awk -v blk="$block" '!done && /^exec .*dwm/ { print blk; done=1 } { print }' \
      "$xi" > "$xi.tmp" && mv "$xi.tmp" "$xi"
  else
    printf '%s\n' "$block" >> "$xi"
  fi
}

wallpaper_apply() {
  local wp; wp=$(state_get dwm/wallpaper)
  if [ "$wp" = "none" ] || [ -z "$wp" ] || [ "$wp" = "off" ]; then
    wallpaper_strip_block
    return 0
  fi
  wallpaper_write_launcher "$wp"
  wallpaper_wire_xinitrc
}
```

- [ ] **Step 4:** In `lib/suckless.sh`, extend the buildable component set so `doomfire` is accepted as a component (uses the same `make clean && make` + `run_with_privilege make install` path as dwm/st — its Makefile follows the same conventions). In `lib/ly.sh`'s animation chooser, after the user picks an animation, when `state_on ly/match_wallpaper`, call `state_set dwm/wallpaper "$(ly_animation_to_wallpaper "$chosen_animation")"` and, for matrix/colormix, `tui_msgbox` the phase-2 notice from the spec.

- [ ] **Step 5:** tests PASS, `shellcheck -x lib/wallpaper.sh` clean, commit `feat: wallpaper launcher + xinitrc wiring, Ly match-wallpaper hook`.

---

### Task 9: Main menu, presets, preview & apply

**Files:**
- Modify: `manjaro-sl.sh` (full implementation), `lib/state.sh` (add `preset_apply`)

**Interfaces:**
- Consumes: everything above.
- Produces: the complete interactive flow per spec "TUI structure", `preset_apply recommended|minimal`, `apply_all` (fixed order: debloat → tweaks → install → build → configure → ly → wallpaper → summary, each via `run_step`).

- [ ] **Step 1: Add `preset_apply` to `lib/state.sh`** (normative — from spec preset table)

```bash
preset_apply() {
  local preset="$1" name desc state
  # debloat-manjaro: on per file defaults; Minimal turns everything on
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) state_set "debloat/$name" "$state" ;;  # file defaults; pamac*/cosmetics/zsh stay off
      minimal)
        case "$name" in
          timeshift|timeshift-autosnap-manjaro|manjaro-zsh-config) state_set "debloat/$name" off ;;
          *) state_set "debloat/$name" on ;;
        esac ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/debloat-manjaro.list")
  # apps: recommended=off, minimal=on except warnings
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) state_set "debloat/$name" off ;;
      minimal)
        case "$name" in
          timeshift|timeshift-autosnap-manjaro) state_set "debloat/$name" off ;;
          *) state_set "debloat/$name" on ;;
        esac ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/debloat-apps.list")
  # printing/bluetooth: off in both presets
  while IFS='|' read -r name desc state; do state_set "debloat/$name" off; done \
    < <(cat <(list_entries "$REPO_ROOT/data/debloat-printing.list") \
            <(list_entries "$REPO_ROOT/data/debloat-bluetooth.list"))
  # recommended installs
  while IFS='|' read -r name desc state; do
    case "$preset" in
      recommended) state_set "install/$name" on ;;
      minimal)     state_set "install/$name" off ;;
    esac
  done < <(list_entries "$REPO_ROOT/data/install-recommended.list")
  # tweaks: NetworkManager + fstrim on in both
  state_set "tweak/enable:NetworkManager.service" on
  state_set "tweak/enable:fstrim.timer" on
  # components + wallpaper
  local c; for c in dwm dmenu st slstatus doomfire; do state_set "component/$c" on; done
  case "$preset" in
    recommended) state_set dwm/wallpaper doomfire; state_set ly/animation doom
                 state_set ly/match_wallpaper on ;;
    minimal)     state_set dwm/wallpaper none ;;
  esac
  state_set ly/enable on
}
```

- [ ] **Step 2: Implement `manjaro-sl.sh` main flow.** Structure (write in full; sub-screens call the module functions):

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for m in exec tui state common packages suckless configure ly debloat tweaks wallpaper; do
  source "$REPO_ROOT/lib/$m.sh"
done

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

install_screen() { ... }     # checklist of components from DEFAULT set + doomfire → SELECTIONS[component/*]
debloat_menu() {             # loops a tui_menu over the four categories + old DE/DM
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
      dedm)      debloat_screen "Old DEs / DMs" "$REPO_ROOT/data/de.list"
                 debloat_screen "Old DMs" "$REPO_ROOT/data/dm.list" ;;
      back|"")   return 0 ;;
    esac
  done
}
dwm_menu() { ... }           # modkey radiolist / bar color / wallpaper radiolist / battery / interface → SELECTIONS + existing configure_* vars
ly_menu() { ... }            # enable checkbox, animation radiolist, match-wallpaper checkbox
preview_text() { ... }       # renders SELECTIONS grouped: REMOVE / INSTALL / BUILD / CONFIGURE / TWEAKS / WALLPAPER
apply_all() {
  run_step "Debloat"        debloat_apply
  run_step "System tweaks"  tweaks_apply
  run_step "Install packages" install_selected_packages   # core + SELECTIONS[install/*] via existing ensure_* path
  run_step "Build components" build_selected_components   # SELECTIONS[component/*] via build_components
  run_step "Configure"       apply_configuration          # configure_* using SELECTIONS values
  run_step "Ly"              configure_ly_display_manager
  run_step "Wallpaper"       wallpaper_apply
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
      reconfig) reconfigure_load ;;   # Task 10
      install)  install_screen ;;
      debloat)  debloat_menu ;;
      dwm)      dwm_menu ;;
      tweaks)   tweaks_screen ;;
      ly)       ly_menu ;;
      preset)   p=$(tui_radiolist "Preset" "Choose" recommended "Recommended" on minimal "Minimal" off) && preset_apply "$p" ;;
      apply)    if tui_yesno "Preview" "$(preview_text)\n\nApply now?"; then apply_all; fi ;;
      quit|"")  break ;;
    esac
  done
}
```

The `...` screens are one `tui_radiolist`/`tui_checklist` call each storing into `SELECTIONS` — follow the `debloat_menu` pattern shown; each reads its current default from `state_get` so revisits show prior choices. `install_selected_packages`, `build_selected_components`, `apply_configuration` are thin adapters mapping `SELECTIONS` onto the existing moved functions' globals (`SLSTATUS_INTERFACE`, `BATTERY_CHOICE`, `BAR_COLOR`, `MODKEY_CHOICE`, `COMPONENTS`).

- [ ] **Step 3: Verify interactively-free paths**

Run: `DRY_RUN=1 TUI_ACTIVE=0 ./manjaro-sl.sh --preset minimal --dry-run --apply` (flag wiring lands in Task 10 — for now verify with: `bash -c 'source manjaro-sl.sh'` syntax check + `bash tests/run-tests.sh` still PASS)
Run: `bash -n manjaro-sl.sh && shellcheck -x manjaro-sl.sh` → clean

- [ ] **Step 4: Manual TUI smoke test** (on this machine, safe): `./manjaro-sl.sh`, visit every menu, select nothing, Quit. No errors.

- [ ] **Step 5: Commit** — `feat: main menu, category screens, presets, preview & apply engine`

---

### Task 10: CLI flags, non-interactive mode, reconfigure mode

**Files:**
- Modify: `manjaro-sl.sh` (arg parsing + `reconfigure_load`)

**Interfaces:**
- Produces: flags `--preset NAME`, `--only SECTION` (repeatable: install|debloat|tweaks|dwm|ly), `--dry-run`, `--profile FILE`, `--apply` (skip TUI, apply current SELECTIONS), `--wallpaper none|doomfire`, generated `--enable-SLUG`/`--disable-SLUG` for every data-file entry (slug = package name; sets `SELECTIONS[debloat/NAME]` etc.), plus ALL legacy flags mapped onto the new state (`--interface X` → `SLSTATUS_INTERFACE`, `--remove-de` → preset the de/dm screens on, `-y` → `TUI_ACTIVE=0` + apply). `reconfigure_load` reads current system state into SELECTIONS.

- [ ] **Step 1: Arg-parsing loop** — extend the existing `while (($#))` pattern from `build_suckless.sh`. Generated flags: after static cases fail, match `--enable-*|--disable-*`:

```bash
--enable-*|--disable-*)
  flag=${1#--}; mode=${flag%%-*}; slug=${flag#*-}
  found=0
  for f in "$REPO_ROOT"/data/debloat-*.list; do
    if list_entries "$f" | cut -d'|' -f1 | grep -qx "$slug"; then
      state_set "debloat/$slug" "$([ "$mode" = enable ] && echo on || echo off)"; found=1
    fi
  done
  if list_entries "$REPO_ROOT/data/install-recommended.list" | cut -d'|' -f1 | grep -qx "$slug"; then
    state_set "install/$slug" "$([ "$mode" = enable ] && echo on || echo off)"; found=1
  fi
  [ "$found" -eq 0 ] && { echo "Unknown flag: $1" >&2; exit 1; }
  ;;
```

- [ ] **Step 2: `reconfigure_load`** — pre-fill SELECTIONS from live system:

```bash
reconfigure_load() {
  # profile first (if present), then live values override
  profile_load "$HOME/.config/manjaro-sl/profile" || true
  # modkey: grep dwm config for current MODKEY
  local cfg="$REPO_ROOT/dwm/config.h"; [ -f "$cfg" ] || cfg="$REPO_ROOT/dwm/config.def.h"
  grep -q 'define MODKEY Mod4Mask' "$cfg" && state_set dwm/modkey super || state_set dwm/modkey alt
  # bar color
  BAR_CURRENT=$(sed -n 's/.*col_accent\[\].*= "\([^"]*\)";.*/\1/p' "$cfg" | head -n1)
  [ -n "$BAR_CURRENT" ] && state_set dwm/barcolor "$BAR_CURRENT"
  # ly animation
  if [ -f /etc/ly/config.ini ]; then
    a=$(grep -E '^\s*animation\s*=' /etc/ly/config.ini | sed 's/.*=\s*//' | tr -d ' ' || true)
    [ -n "$a" ] && state_set ly/animation "$a"
    systemctl is-enabled ly.service >/dev/null 2>&1 || systemctl is-enabled 'ly@*.service' >/dev/null 2>&1 \
      && state_set ly/enable on
  fi
  # wallpaper: presence of the marked block
  grep -q 'manjaro-sl wallpaper' "$HOME/.xinitrc" 2>/dev/null \
    && state_set dwm/wallpaper doomfire || state_set dwm/wallpaper none
  tui_msgbox "Reconfigure" "Current settings loaded — visit any menu to change them, then Preview & Apply."
}
```

- [ ] **Step 3: Non-interactive smoke tests** (the CI path)

Run: `./manjaro-sl.sh --preset minimal --dry-run --apply 2>&1 | tee /tmp/dryrun.txt`
Expected: output contains `+ sudo pacman -Rns` (with manjaro-hello etc.), `+ sudo systemctl enable NetworkManager.service`, `+ sudo pacman -Syu --needed`, no actual system change (`pacman -Qi manjaro-hello` still succeeds).
Run: `./manjaro-sl.sh --preset recommended --dry-run --apply | grep -c pamac` → `0` (pamac not removed in Recommended).
Run: `./manjaro-sl.sh --disable-manjaro-hello --preset minimal --dry-run --apply | grep 'Rns'` → line does NOT contain `manjaro-hello` (flag order: flags after preset override).

Note: process flags left-to-right; `--preset` applies when parsed, so later `--enable/--disable` flags override it. Document in `--help`.

- [ ] **Step 4:** `shellcheck -x manjaro-sl.sh` clean; commit `feat: CLI flags, non-interactive apply, reconfigure mode`.

---

### Task 11: Legacy wrapper + help text

**Files:**
- Rewrite: `build_suckless.sh` (wrapper only; the sourced-module version from Task 4 is superseded once `manjaro-sl.sh` owns the flow)
- Modify: `manjaro-sl.sh` (`usage()` covering every flag)

- [ ] **Step 1: Replace `build_suckless.sh` with:**

```bash
#!/usr/bin/env bash
# DEPRECATED: build_suckless.sh has been replaced by manjaro-sl.sh.
# This wrapper forwards to the new entry point's install-only mode.
echo "build_suckless.sh is deprecated — use ./manjaro-sl.sh (forwarding to it now)." >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manjaro-sl.sh" --only install "$@"
```

- [ ] **Step 2:** Write the full `usage()` in `manjaro-sl.sh`: every flag from Task 10 with one-line descriptions, the flag-ordering note, examples mirroring the old README block (`--preset minimal --dry-run --apply`, `-y`, `--interface wlan0 --battery`, etc.).
- [ ] **Step 3:** Run: `./build_suckless.sh --help` → prints deprecation line + new usage; `./manjaro-sl.sh --help` exit 0.
- [ ] **Step 4:** Commit `feat: deprecate build_suckless.sh as forwarding wrapper`.

---

### Task 12: README rewrite + repo rename references

**Files:**
- Rewrite: `readme.md`
- Modify: `bug_report_and_recommendations.md` (repo name reference)

- [ ] **Step 1: Rewrite `readme.md`** with structure:
  1. Title `# manjaro-sl` + one-paragraph pitch (customized DWM setup **and** Manjaro debloater, WinUtil-inspired TUI, from-scratch doomfire wallpaper).
  2. Quick start: `git clone https://github.com/BirchWoodGod/manjaro-sl && cd manjaro-sl && ./manjaro-sl.sh`.
  3. Screenshot placeholder section for the TUI (leave an HTML comment `<!-- TODO: screenshot after first release -->` — allowed in README, not in code).
  4. What it does: the 8 menu sections, presets table from the spec, debloat categories + safety rails (denylist, -Rns only, removal logs, DM never stopped), wallpaper section (doomfire now, xmatrix/colormix phase 2, FPS/CPU note).
  5. Non-interactive usage: all flags with the Task 10 examples, `--dry-run` highlighted.
  6. Reconfigure mode paragraph.
  7. Manual reference: keep the existing manual-setup content (multilib, packages, Ly, xinitrc, per-component `make`), updated paths/names.
  8. j4-dmenu-desktop licensing note (keep as-is).
- [ ] **Step 2:** In `bug_report_and_recommendations.md` line 7: `BirchWoodGod/sl` → `BirchWoodGod/manjaro-sl`.
- [ ] **Step 3:** Commit `docs: rewrite README for manjaro-sl dual purpose`.

---

### Task 13: Final verification sweep

- [ ] `bash tests/run-tests.sh` → 0 failures.
- [ ] `shellcheck -x manjaro-sl.sh build_suckless.sh lib/*.sh` → clean.
- [ ] `make -C doomfire clean && make -C doomfire && make -C doomfire test` → pass.
- [ ] `./manjaro-sl.sh --preset minimal --dry-run --apply` → full dry-run transcript, zero system mutations (verify `pacman -Qi manjaro-hello` unchanged before/after).
- [ ] `./manjaro-sl.sh --preset recommended --dry-run --apply | grep -E 'Rns.*pamac'` → no output.
- [ ] Interactive spot-check: `./manjaro-sl.sh` → every menu opens, Quit works, warnings show on `manjaro-zsh-config` / `timeshift` rows (desc text).
- [ ] `git status` clean; final commit if stragglers.

### Post-merge manual steps (user, not the executor)

1. `sudo pacman -S github-cli && gh auth login && gh repo rename manjaro-sl`
2. `git remote set-url origin https://github.com/BirchWoodGod/manjaro-sl.git`
3. Optionally rename the local directory `~/github/sl` → `~/github/manjaro-sl`.
