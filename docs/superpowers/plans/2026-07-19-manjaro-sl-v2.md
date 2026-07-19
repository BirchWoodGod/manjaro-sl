# manjaro-sl v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the legacy wrapper and tidy the root, collapse the 9-item TUI into 7 task-oriented menus with auto-preloaded state, and ship `xmatrix` (green digital-rain desktop wallpaper) so the matrix choice works on both login screen and desktop — per `docs/superpowers/specs/2026-07-19-manjaro-sl-v2-design.md`.

**Architecture:** TUI-only restructuring of `manjaro-sl.sh` (state keys and CLI flags untouched); `xmatrix/` is a standalone suckless-C program mirroring `doomfire/`; repo cleanup is deletions/moves plus test retargeting.

**Tech Stack:** bash 5, whiptail, C99 + libX11 (core fonts, no Xft), existing test runner.

## Global Constraints

- State keys unchanged: `ly/animation`, `dwm/wallpaper`, `ly/match_wallpaper`, `ly/enable`, `component/*`, `dwm/*`. CLI flag surface unchanged.
- xmatrix links ONLY libX11; compiles warning-free under `-std=c99 -pedantic -Wall -Wextra -Os`; suckless conventions (`config.def.h` → `config.h`, `config.mk`, MIT LICENSE, `-n N` test flag).
- `bash -n` on all changed shell files (shellcheck not installed). Full suite `bash tests/run-tests.sh` green at every commit; no real system mutations in tests (DRY_RUN/mocks/sandboxed HOME only). No sudo.
- Wallpaper mapping after this plan: `doom→doomfire`, `matrix→xmatrix`, everything else→`none`.
- Menu after this plan, exactly 7 entries: Desktop Setup / Appearance / Debloat Manjaro / System Tweaks / Presets / Preview & Apply / Quit.

## File Structure (final deltas)

```
DELETE  build_suckless.sh
MOVE    bug_report_and_recommendations.md → docs/bug_report_and_recommendations.md
MODIFY  .gitignore                 (+ dmenu/j4-dmenu-desktop/subprojects/.wraplock)
CREATE  xmatrix/{main.c,config.def.h,config.mk,Makefile,LICENSE,.gitignore}
MODIFY  lib/wallpaper.sh           (matrix→xmatrix mapping)
MODIFY  lib/suckless.sh            (xmatrix in clean_build_artifacts)
MODIFY  manjaro-sl.sh              (menu restructure, detect_existing_setup, Appearance)
MODIFY  tests/lib-tests.sh         (retarget wrapper tests; new tests)
MODIFY  readme.md                  (migration table, Appearance section)
```

---

### Task 1: Repo organization

**Files:**
- Delete: `build_suckless.sh`
- Move: `bug_report_and_recommendations.md` → `docs/bug_report_and_recommendations.md`
- Modify: `.gitignore`, `tests/lib-tests.sh`, `readme.md`

**Interfaces:**
- Produces: a repo with no `build_suckless.sh`; later tasks assume it's gone.

- [ ] **Step 1: Retarget/remove wrapper tests (TDD: change tests first, watch them fail for the right reason).** In `tests/lib-tests.sh` find every test invoking `build_suckless.sh` (grep for it). There are: the nosudo `--help` test and the wrapper-forwarding tests (deprecation stderr + positional `st`). Delete the wrapper-specific assertions (deprecation line, wrapper forwarding) — equivalents exist for `manjaro-sl.sh` (nosudo `--help`, positional `st` direct). Where a `build_suckless.sh` test checks something with NO direct manjaro-sl equivalent (check first — the positional-`st`-direct test exists from Task 11 fixes), keep the scenario but point it at `./manjaro-sl.sh`. Add one new assertion:

```bash
# repo org: the legacy wrapper is gone
assert_fail test -e "$REPO_ROOT/build_suckless.sh"
```

- [ ] **Step 2: Run suite** — the new assertion FAILS (file still exists); retargeted tests pass.
- [ ] **Step 3: Apply the org changes**

```bash
git rm build_suckless.sh
git mv bug_report_and_recommendations.md docs/
printf 'dmenu/j4-dmenu-desktop/subprojects/.wraplock\n' >> .gitignore
```

- [ ] **Step 4: README migration note.** In `readme.md`, replace the build_suckless.sh deprecation-wrapper paragraph with a "Migrating from build_suckless.sh" subsection containing this table:

```markdown
| Old | New |
|---|---|
| `./build_suckless.sh` | `./manjaro-sl.sh -y` |
| `./build_suckless.sh st dwm` | `./manjaro-sl.sh st dwm -y` |
| `./build_suckless.sh --interface wlan0 --battery -y` | `./manjaro-sl.sh --interface wlan0 --battery -y` |
| `./build_suckless.sh --skip-packages -y` | `./manjaro-sl.sh --skip-packages -y` |
```

Also update any remaining `build_suckless.sh` invocation examples elsewhere in the README (grep it).

- [ ] **Step 5: Verify + commit.** `bash tests/run-tests.sh` all green; `git status` clean except intended changes.

```bash
git add -A && git commit -m "chore: remove legacy wrapper, move bug report to docs, ignore .wraplock"
```

---

### Task 2: xmatrix — green digital rain wallpaper

**Files:**
- Create: `xmatrix/main.c`, `xmatrix/config.def.h`, `xmatrix/config.mk`, `xmatrix/Makefile`, `xmatrix/LICENSE` (MIT, `Copyright (c) 2026 BirchWoodGod`), `xmatrix/.gitignore` (`xmatrix` + `config.h` lines)

**Interfaces:**
- Produces: `xmatrix` binary installing to `/usr/local/bin/xmatrix`; `-n N` renders N frames then exits; exits 1 with `xmatrix: cannot open display` when no X.

- [ ] **Step 1: `xmatrix/config.def.h`** (verbatim)

```c
/* xmatrix configuration — copy to config.h and edit, suckless-style */

/* frames per second (CPU cost scales roughly linearly) */
static const int FPS = 24;

/* glyph cell size in pixels */
static const int CELL_W = 10;
static const int CELL_H = 16;

/* target fraction of columns with an active drop, and per-frame spawn
 * probability for an idle column while below that target */
static const double DENSITY = 0.60;
static const double SPAWN_P = 0.03;

/* X11 core font (no Xft); "fixed" exists everywhere */
static const char FONTNAME[] = "fixed";

/* glyphs cycled at random */
static const char CHARSET[] =
    "abcdefghijklmnopqrstuvwxyz0123456789$+-*/=%\"'#&_(),.;:?!|{}<>[]^~";

/* tail color (16-bit channels) and head color */
static const unsigned short TAIL_R = 0x0000, TAIL_G = 0xffff, TAIL_B = 0x4600;
static const unsigned short HEAD_R = 0xcccc, HEAD_G = 0xffff, HEAD_B = 0xcccc;

/* number of brightness shades in the tail */
enum { NSHADES = 8 };
```

- [ ] **Step 2: `xmatrix/main.c`** (verbatim)

```c
/* xmatrix — Matrix-style digital rain on the X11 root window.
 * Same root-pixmap technique as doomfire. libX11 core fonts only.
 * MIT licensed. */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "config.h"

typedef struct {
    int active;
    int head;   /* row of the drop's head */
    int len;    /* tail length in cells */
    int speed;  /* advance one row every `speed` frames */
    int tick;
} Drop;

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static unsigned long alloc_shade(Display *dpy, int scr, double f) {
    XColor c;
    c.red   = (unsigned short)(TAIL_R * f);
    c.green = (unsigned short)(TAIL_G * f);
    c.blue  = (unsigned short)(TAIL_B * f);
    c.flags = DoRed | DoGreen | DoBlue;
    if (!XAllocColor(dpy, DefaultColormap(dpy, scr), &c))
        return WhitePixel(dpy, scr);
    return c.pixel;
}

int main(int argc, char *argv[]) {
    int frames = -1;                    /* -1 = run forever */
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);         /* -n N: render N frames and exit */

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xmatrix: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);

    XFontStruct *font = XLoadQueryFont(dpy, FONTNAME);
    if (!font) font = XLoadQueryFont(dpy, "fixed");
    if (!font) font = XLoadQueryFont(dpy, "*");
    if (!font) { fprintf(stderr, "xmatrix: no usable core font\n"); return 1; }
    XSetFont(dpy, gc, font->fid);

    int cols = sw / CELL_W;
    int rows = sh / CELL_H + 1;
    if (cols < 1) cols = 1;
    Drop *drops = calloc((size_t)cols, sizeof(Drop));
    if (!drops) { fprintf(stderr, "xmatrix: oom\n"); return 1; }

    unsigned long shades[NSHADES];
    for (int i = 0; i < NSHADES; i++)
        shades[i] = alloc_shade(dpy, scr, (double)(NSHADES - i) / NSHADES);
    XColor hc;
    hc.red = HEAD_R; hc.green = HEAD_G; hc.blue = HEAD_B;
    hc.flags = DoRed | DoGreen | DoBlue;
    unsigned long head_px = XAllocColor(dpy, DefaultColormap(dpy, scr), &hc)
        ? hc.pixel : WhitePixel(dpy, scr);
    unsigned long black = BlackPixel(dpy, scr);

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);

    struct timespec tickts = {0, 1000000000L / FPS};
    srand((unsigned)time(NULL));
    int charset_n = (int)strlen(CHARSET);

    while (running && frames != 0) {
        /* spawn new drops while below the density target */
        int active = 0;
        for (int c = 0; c < cols; c++) active += drops[c].active;
        for (int c = 0; c < cols && active < (int)(DENSITY * cols); c++) {
            if (!drops[c].active && (double)rand() / RAND_MAX < SPAWN_P) {
                drops[c].active = 1;
                drops[c].head = 0;
                drops[c].len = rows / 4 + rand() % (rows / 2 + 1);
                drops[c].speed = 1 + rand() % 3;
                drops[c].tick = 0;
                active++;
            }
        }

        /* draw the frame */
        XSetForeground(dpy, gc, black);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);
        for (int c = 0; c < cols; c++) {
            if (!drops[c].active) continue;
            for (int i = 0; i < drops[c].len; i++) {
                int row = drops[c].head - i;
                if (row < 0 || row >= rows) continue;
                if (i == 0) XSetForeground(dpy, gc, head_px);
                else XSetForeground(dpy, gc,
                    shades[i * NSHADES / drops[c].len]);
                char g[2] = { CHARSET[rand() % charset_n], 0 };
                XDrawString(dpy, pm, gc, c * CELL_W,
                            row * CELL_H + font->ascent, g, 1);
            }
        }

        /* advance drops */
        for (int c = 0; c < cols; c++) {
            if (!drops[c].active) continue;
            if (++drops[c].tick >= drops[c].speed) {
                drops[c].tick = 0;
                drops[c].head++;
                if (drops[c].head - drops[c].len > rows)
                    drops[c].active = 0;
            }
        }

        XChangeProperty(dpy, root, prop_root, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XChangeProperty(dpy, root, prop_eset, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XSetWindowBackgroundPixmap(dpy, root, pm);
        XClearWindow(dpy, root);
        XFlush(dpy);
        if (frames > 0) frames--;
        nanosleep(&tickts, NULL);
    }

    free(drops);
    XFreeFont(dpy, font);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3: `xmatrix/config.mk` + `xmatrix/Makefile`** — copy `doomfire/config.mk` and `doomfire/Makefile` verbatim, then replace every `doomfire` occurrence with `xmatrix` (binary name, test invocation). Keep the `-D_POSIX_C_SOURCE=200809L` CPPFLAG and the `;`-joined Xvfb test recipe exactly as doomfire has them.
- [ ] **Step 4: LICENSE + .gitignore** — MIT text with `Copyright (c) 2026 BirchWoodGod`; `.gitignore` containing `xmatrix` and `config.h`.
- [ ] **Step 5: Build + verify.** `make -C xmatrix` → zero warnings. `make -C xmatrix test` → Xvfb skip, exit 0. `env -u DISPLAY ./xmatrix/xmatrix -n 3; echo $?` → `xmatrix: cannot open display`, exit 1. `make -C xmatrix clean`.
- [ ] **Step 6: Commit** — `git add xmatrix/ && git commit -m "feat: xmatrix — digital-rain X11 root-window wallpaper"`

---

### Task 3: Wire xmatrix into the wallpaper/build machinery

**Files:**
- Modify: `lib/wallpaper.sh` (mapping), `lib/suckless.sh` (clean_build_artifacts), `tests/lib-tests.sh`

**Interfaces:**
- Consumes: `ly_animation_to_wallpaper` (lib/wallpaper.sh), `clean_build_artifacts` binaries list (lib/suckless.sh — see how doomfire was added).
- Produces: `ly_animation_to_wallpaper matrix` → `xmatrix`; `xmatrix` cleanable/buildable as a component.

- [ ] **Step 1: Failing tests** (append to `tests/lib-tests.sh`; note an EXISTING assertion says `ly_animation_to_wallpaper matrix` → `none` — update that one to expect `xmatrix`):

```bash
assert_eq "$(ly_animation_to_wallpaper matrix)" "xmatrix"
assert_eq "$(ly_animation_to_wallpaper colormix)" "none"
```

- [ ] **Step 2: Run** — FAIL (matrix still maps to none).
- [ ] **Step 3: Implement.** In `lib/wallpaper.sh`:

```bash
ly_animation_to_wallpaper() {
  case "$1" in
    doom)   echo doomfire ;;
    matrix) echo xmatrix ;;
    *)      echo none ;;   # colormix/custom are not yet built for the desktop
  esac
}
```

In `lib/suckless.sh`, add `xmatrix` wherever `doomfire` appears in `clean_build_artifacts` (binaries and build-dir arrays — grep `doomfire` there and mirror it).

- [ ] **Step 4: Component check.** `./manjaro-sl.sh xmatrix --dry-run --apply --skip-packages` (sandboxed HOME) → Build note shows `selected: xmatrix`, exit 0. Update the positional-validation list in `manjaro-sl.sh` parse_args (`valid_comps`) to include `xmatrix`, and the unknown-component error message text to match. Also add `xmatrix` to the Desktop Setup component checklist entries (grep for the checklist args where doomfire is listed).
- [ ] **Step 5: Suite green; commit** — `feat: wire xmatrix into wallpaper mapping and component machinery`

---

### Task 4: Auto-preload — detect_existing_setup replaces the Reconfigure item

**Files:**
- Modify: `manjaro-sl.sh`, `tests/lib-tests.sh`

**Interfaces:**
- Consumes: `reconfigure_load` + `reconfigure_read_slstatus` (current manjaro-sl.sh).
- Produces: `detect_existing_setup` (same body as reconfigure_load minus the closing msgbox, returns 0 always, sets global `EXISTING_SETUP=1` when any signal found: dwm binary via `command -v dwm`, `/etc/ly/config.ini` exists, or `~/.xinitrc` exists); `SETUP_BANNER` global ("existing setup detected — current settings loaded" or "fresh setup"). `reconfigure_load` name is gone.

- [ ] **Step 1: Failing tests.** `detect_existing_setup` must be directly callable; with a sandboxed HOME containing an `.xinitrc` it sets the banner; with an empty sandbox HOME and dwm/ly absent from a stripped PATH it reports fresh:

```bash
# detect_existing_setup: existing vs fresh
OLD_HOME=$HOME; export HOME=$(mktemp -d)
touch "$HOME/.xinitrc"
EXISTING_SETUP=0; SETUP_BANNER=""
detect_existing_setup
assert_eq "$EXISTING_SETUP" "1"
assert_contains "$SETUP_BANNER" "existing setup detected"
rm -f "$HOME/.xinitrc"
# fresh: no xinitrc; dwm/ly detection uses command -v / file checks that
# depend on the host — force fresh by overriding the helpers:
command_v_real=$(command -v dwm || true)
EXISTING_SETUP=0; SETUP_BANNER=""
XINITRC_OVERRIDE="" LY_CONFIG_OVERRIDE="/nonexistent" DWM_CHECK_OVERRIDE=missing detect_existing_setup
assert_eq "$EXISTING_SETUP" "0"
assert_contains "$SETUP_BANNER" "fresh setup"
HOME=$OLD_HOME
```

Implementation note that makes this testable: `detect_existing_setup` reads `LY_CONFIG_OVERRIDE` (default `/etc/ly/config.ini`) and `DWM_CHECK_OVERRIDE` (when set to `missing`, skip the `command -v dwm` signal) — small seams, defaulting to real behavior.

- [ ] **Step 2: Run** — FAIL (function undefined).
- [ ] **Step 3: Implement.** Rename `reconfigure_load` → `detect_existing_setup`; add the signal check + banner + `EXISTING_SETUP` global + the two override seams; drop its closing `tui_msgbox`. Call it unconditionally in `main()` before `main_menu` (and NOT in `--apply` non-interactive path — flags/presets rule there; preserve current non-interactive behavior which never called reconfigure_load). Remove the `reconfig` menu item and its case arm. Show `$SETUP_BANNER` in the main menu prompt text (`tui_menu "manjaro-sl" "$SETUP_BANNER — Main menu" ...`).
- [ ] **Step 4: Menu integrity test:**

```bash
# main menu: 7 entries, no reconfig/install/ly items
menu_src=$(grep -A15 'tui_menu "manjaro-sl"' "$REPO_ROOT/manjaro-sl.sh")
assert_contains "$menu_src" "Desktop Setup"
assert_contains "$menu_src" "Appearance"
assert_eq "$(echo "$menu_src" | grep -c 'Reconfigure')" "0"
```

(This asserts against source text — acceptable here because the menu args are static strings; the interactive path itself is exercised by the existing TUI_ACTIVE=0 fallback tests.) Note: this test belongs to Task 5's commit if the Appearance entry doesn't exist yet — write it expecting the FINAL menu and mark it into Task 5 if it fails early. Coordinate: implement Task 4 with the menu still containing the old dwm/install/ly items EXCEPT reconfig removed; the count-to-7 assertion lands in Task 5.
- [ ] **Step 5: Suite green (`bash tests/run-tests.sh`); `./manjaro-sl.sh --help` exit 0; commit** — `feat: auto-preload existing setup, remove Reconfigure menu item`

---

### Task 5: Desktop Setup + Appearance menus

**Files:**
- Modify: `manjaro-sl.sh`, `tests/lib-tests.sh`

**Interfaces:**
- Consumes: existing screen functions (`install_screen`, `dwm_menu` internals, `ly_menu` internals), `tui_radiolist`, `tui_input`, `tui_yesno`, `state_*`, `ly_animation_to_wallpaper`.
- Produces: `desktop_setup_menu` (fuses component checklist + modkey/color/interface/battery items), `appearance_menu` (unified animation radiolist + Custom… + Advanced + Ly-enable checkbox). Old `install_screen`/`dwm_menu`/`ly_menu` entrances removed from the main menu (their internals may be reused/renamed).

- [ ] **Step 1: Failing tests** (TUI_ACTIVE=0 fallback driving, mirroring existing menu tests):

```bash
# appearance: unified choice writes both keys and match flag
declare -gA SELECTIONS=()
TUI_ACTIVE=0
appearance_menu <<< "2
"    # pick entry 2 = matrix in the unified radiolist, then exit the menu loop
assert_eq "$(state_get ly/animation)" "matrix"
assert_eq "$(state_get dwm/wallpaper)" "xmatrix"
assert_eq "$(state_get ly/match_wallpaper)" "on"
```

Adapt the herestring to the actual fallback prompt sequence you implement (the fallback radiolist reads one number; if appearance_menu loops, feed the exit choice too). Additionally:

```bash
# custom animation: verbatim ly value, desktop falls back to none
declare -gA SELECTIONS=()
appearance_menu <<< "5
blackhole
"   # 5 = Custom…, then the name
assert_eq "$(state_get ly/animation)" "blackhole"
assert_eq "$(state_get dwm/wallpaper)" "none"
```

And the Task-4 menu-integrity test completed to the final 7-entry assertion (Desktop Setup present, Appearance present, no `Install DWM`, no `Ly Display Manager` top-level item, no `Configure DWM`).

- [ ] **Step 2: Run** — FAIL (functions undefined).
- [ ] **Step 3: Implement.**
  - `desktop_setup_menu`: a `tui_menu` loop offering Components / Modkey / Bar color / Network interface / Battery / Back — each case calls the existing logic currently inside `install_screen` and `dwm_menu` (move those code blocks; delete the old wrapper functions and their main-menu entries). Wallpaper is NOT here.
  - `appearance_menu`: `tui_menu` loop offering: Animation (unified radiolist doom/matrix/colormix/none/custom, current value pre-selected from `state_get ly/animation`), Advanced (two separate radiolists: Ly animation incl. custom; desktop wallpaper none/doomfire/xmatrix — sets `ly/match_wallpaper off`), "Enable Ly on boot" (yes/no via tui_radiolist storing `ly/enable`), Back. Unified path: `state_set ly/animation X`, `state_set dwm/wallpaper "$(ly_animation_to_wallpaper X)"`, `state_set ly/match_wallpaper on`; when the mapping returns `none` for a non-none animation, show the existing phase-2 style msgbox notice. Custom…: `tui_input "Ly animation" "Animation name" "$(state_get ly/animation)"`, trim, store verbatim.
  - Main menu: exactly `desktop "Desktop Setup"  appearance "Appearance"  debloat "Debloat Manjaro"  tweaks "System Tweaks"  preset "Presets"  apply "Preview & Apply"  quit "Quit"` with `$SETUP_BANNER` in the prompt.
- [ ] **Step 4: Suite green; interactive spot-check** `./manjaro-sl.sh` (visit each menu, quit — controller may substitute a TUI_ACTIVE=0 scripted walk if no tty). `bash -n manjaro-sl.sh`.
- [ ] **Step 5: Commit** — `feat: task-oriented menu — Desktop Setup + Appearance, 7-item main menu`

---

### Task 6: README + final verification

**Files:**
- Modify: `readme.md`

- [ ] **Step 1: README updates.** Menu documentation section rewritten to the 7 items (reuse the spec's menu block); Appearance section explains the unified choice, Advanced split, Custom… (pointing at Ly's community animations for e.g. black hole `.dur` files), and the mapping table (doom→doomfire, matrix→xmatrix, others→none until phase 3); auto-preload paragraph replaces the Reconfigure-mode section (behavior: settings always loaded at startup when an existing setup is detected); wallpaper section lists doomfire + xmatrix as built, xcolormix/xblackhole as phase 3.
- [ ] **Step 2: Accuracy pass.** Every documented command run with `--dry-run`/`--help` verification as in v1 Task 12. Grep README for `build_suckless` — only the migration table may mention it.
- [ ] **Step 3: Full verification matrix.** `bash tests/run-tests.sh` → 0 FAIL; `bash -n manjaro-sl.sh lib/*.sh`; `make -C xmatrix && make -C xmatrix test && make -C xmatrix clean`; `make -C doomfire && make -C doomfire clean`; sandboxed `./manjaro-sl.sh --preset recommended --dry-run --apply` exit 0; sandboxed `./manjaro-sl.sh xmatrix --dry-run --apply --skip-packages` selects only xmatrix; `git status` clean.
- [ ] **Step 4: Commit** — `docs: README for v2 menu, xmatrix, migration from build_suckless.sh`
