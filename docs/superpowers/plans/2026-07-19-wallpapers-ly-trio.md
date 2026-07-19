# Wallpapers Plan 1: Registry + Ly Trio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the scattered hardcoded wallpaper lists with one registry, then ship xcolormix, xgameoflife, and xblackhole so every Ly animation (plus the community black hole) has a desktop match — per `docs/superpowers/specs/2026-07-19-wallpapers-phase3-design.md` (plan 2 will add the four customs).

**Architecture:** `lib/wallpaper.sh` owns `KNOWN_WALLPAPERS`/`WALLPAPER_DESCS`/`is_known_wallpaper`; every consumer derives from it, gated on directory existence so plan-2 names stay invisible. The three new programs are standalone suckless-C dirs on the doomfire/xmatrix template, all libX11-only (no libm — xblackhole uses a precomputed rotation matrix and rejection sampling instead of trig).

**Tech Stack:** bash 5, C99 + libX11, existing test runner (currently 217 assertions).

## Global Constraints

- Every wallpaper program: standalone dir with `main.c`, `config.def.h`, `config.mk`, `Makefile`, MIT LICENSE (`Copyright (c) 2026 BirchWoodGod`), `.gitignore` (binary + config.h); `-n N` frames flag; `<name>: cannot open display` → exit 1; root pixmap + `_XROOTPMAP_ID`/`ESETROOT_PMAP_ID` atoms + `XSetWindowBackgroundPixmap` + `XClearWindow` per frame; warning-free under `-std=c99 -pedantic -Wall -Wextra -Os`; links ONLY `-lX11` (no `-lm`); `make test` via Xvfb with clean skip (Xvfb absent on this machine — skip IS the expected outcome).
- `config.mk`/`Makefile`/LICENSE/.gitignore: copy from `xmatrix/`, replacing every `xmatrix` with the new name; keep `-D_POSIX_C_SOURCE=200809L` and the `;`-joined test recipe exactly.
- Registry refactor is behavior-preserving: derived lists must equal today's hardcoded behavior for doomfire/xmatrix before any new program lands.
- bash -n on all changed shell files (shellcheck not installed); suite green at every commit; no sudo; sandboxed HOME + --dry-run only in tests.
- State keys and CLI flag names unchanged (only `--wallpaper`'s accepted VALUES grow, via the registry).

---

### Task 1: Wallpaper registry

**Files:**
- Modify: `lib/wallpaper.sh`, `manjaro-sl.sh`, `lib/suckless.sh`, `tests/lib-tests.sh`

**Interfaces:**
- Produces: in `lib/wallpaper.sh`: `KNOWN_WALLPAPERS` (indexed array: doomfire xmatrix xcolormix xgameoflife xblackhole xstarfield xplasma xrain xfireflies), `WALLPAPER_DESCS` (assoc array, one entry per name — descriptions below), `is_known_wallpaper NAME` (exit 0/1), `available_wallpapers` (echoes registry members whose `$REPO_ROOT/<name>` dir exists, one per line, registry order). Consumers rewritten to derive from these.

- [ ] **Step 1: Failing tests** (append to `tests/lib-tests.sh`):

```bash
# wallpaper registry
assert_ok is_known_wallpaper doomfire
assert_ok is_known_wallpaper xblackhole
assert_fail is_known_wallpaper spinningcube
# available = registry ∩ existing dirs; right now only doomfire+xmatrix exist
avail=$(available_wallpapers | tr '\n' ' ')
assert_eq "$avail" "doomfire xmatrix "
# every registry member has a description
for w in "${KNOWN_WALLPAPERS[@]}"; do
  assert_ok test -n "${WALLPAPER_DESCS[$w]:-}"
done
```

- [ ] **Step 2: Run** — FAIL (functions undefined).
- [ ] **Step 3: Implement the registry** at the top of `lib/wallpaper.sh` (after the block markers):

```bash
# Single source of truth for desktop wallpapers. A registry entry may exist
# before its program ships — consumers gate on available_wallpapers (directory
# exists) so unbuilt names never surface in menus or validation.
KNOWN_WALLPAPERS=(doomfire xmatrix xcolormix xgameoflife xblackhole
                  xstarfield xplasma xrain xfireflies)
declare -gA WALLPAPER_DESCS=(
  [doomfire]="DOOM fire X11 wallpaper animation"
  [xmatrix]="Matrix rain X11 wallpaper animation"
  [xcolormix]="Shifting color gradients wallpaper animation"
  [xgameoflife]="Conway's Game of Life wallpaper animation"
  [xblackhole]="Black hole accretion-disk wallpaper animation"
  [xstarfield]="Flying starfield wallpaper animation"
  [xplasma]="Demoscene plasma wallpaper animation"
  [xrain]="Falling rain wallpaper animation"
  [xfireflies]="Drifting fireflies wallpaper animation"
)

is_known_wallpaper() {
  local w
  for w in "${KNOWN_WALLPAPERS[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

available_wallpapers() {
  local w
  for w in "${KNOWN_WALLPAPERS[@]}"; do
    [ -d "$REPO_ROOT/$w" ] && echo "$w"
  done
}
```

- [ ] **Step 4: Rewrite the consumers** (grep each site; keep behavior identical given only doomfire/xmatrix exist):
  - `manjaro-sl.sh` `select_wallpaper`: replace `case "$wp" in doomfire|xmatrix)` with `if is_known_wallpaper "$wp"; then state_set "component/$wp" on; WALLPAPER_IMPLIED["component/$wp"]=1; fi`.
  - `manjaro-sl.sh` `parse_args` `valid_comps`: build as `local -a valid_comps=(dwm dmenu st slstatus); while IFS= read -r w; do valid_comps+=("$w"); done < <(available_wallpapers)`; error message prints `${valid_comps[*]}`.
  - `manjaro-sl.sh` `--wallpaper` arm: accept `none` or `available_wallpapers` members (`is_known_wallpaper "$2" && [ -d "$REPO_ROOT/$2" ]` — or match against available_wallpapers output); error message prints `'none', $(available_wallpapers | tr '\n' ' ')` style dynamic list.
  - `manjaro-sl.sh` Desktop Setup component checklist: comps = `dwm dmenu st slstatus` + `available_wallpapers`; descriptions for wallpapers from `WALLPAPER_DESCS` (keep the four base descs where they are).
  - `manjaro-sl.sh` Advanced desktop-wallpaper radiolist in `appearance_menu`: entries = `none` + `available_wallpapers` with descs, current value pre-selected.
  - `manjaro-sl.sh` `detect_existing_setup` launcher check: `is_known_wallpaper "$wp"` instead of the hardcoded case.
  - `lib/suckless.sh` `clean_build_artifacts`: binaries list += loop over `available_wallpapers` (`"$REPO_ROOT/$w/$w"`), components-dirs list likewise; delete the hardcoded doomfire/xmatrix wallpaper entries (dwm/dmenu/st/slstatus/j4 entries stay). Note lib/suckless.sh is sourced before lib/wallpaper.sh in some paths — make clean_build_artifacts call `available_wallpapers` at RUN time (function body), and guard with `declare -F available_wallpapers` falling back to the current hardcoded pair for the legacy source order.
- [ ] **Step 5: Equivalence checks** — full suite must stay green UNCHANGED (the existing xmatrix/doomfire positional, --wallpaper, checklist, and detection tests are the equivalence proof), plus Step 1's new assertions. Run `bash tests/run-tests.sh` → 222/0 expected (217 + 5 new; adjust count to reality). `bash -n` all changed files. Sandboxed `./manjaro-sl.sh --wallpaper xmatrix -y --dry-run` build line contains dwm+xmatrix (implied-seeding regression stays green).
- [ ] **Step 6: Commit** — `refactor: single wallpaper registry drives all component/menu/validation lists`

---

### Task 2: xcolormix

**Files:**
- Create: `xcolormix/main.c`, `xcolormix/config.def.h`, `xcolormix/config.mk`, `xcolormix/Makefile`, `xcolormix/LICENSE`, `xcolormix/.gitignore`

**Interfaces:**
- Produces: `xcolormix` binary (installs `/usr/local/bin/xcolormix`); `-n N`; no-display → `xcolormix: cannot open display`, exit 1.

- [ ] **Step 1: `xcolormix/config.def.h`** (verbatim)

```c
/* xcolormix configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* render buffer, scaled to the screen (smaller = less CPU) */
static const int BUF_W = 320;
static const int BUF_H = 180;

/* anchor hues (degrees, 0-360) blended left-to-right across the screen;
 * the whole palette also rotates one full wheel every CYCLE_SEC seconds */
static const float ANCHORS[] = { 200.0f, 280.0f, 340.0f, 40.0f };
static const int CYCLE_SEC = 60;

/* saturation and value, 0..1 */
static const float SAT = 0.85f;
static const float VAL = 0.55f;
```

- [ ] **Step 2: `xcolormix/main.c`** (verbatim)

```c
/* xcolormix — slowly shifting color gradients on the X11 root window.
 * Same root-pixmap technique as doomfire. libX11 only, no libm. */
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

#define NANCHORS ((int)(sizeof(ANCHORS) / sizeof(ANCHORS[0])))

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static float wrap360(float h) {
    while (h >= 360.0f) h -= 360.0f;
    while (h < 0.0f) h += 360.0f;
    return h;
}

/* h in [0,360), s/v in [0,1] -> 0xRRGGBB. Sector algorithm, no libm. */
static unsigned long hsv_pixel(float h, float s, float v) {
    float c = v * s;
    float hp = h / 60.0f;
    float m2 = hp;                       /* hp mod 2 without fmod */
    while (m2 >= 2.0f) m2 -= 2.0f;
    float x = c * (1.0f - (m2 - 1.0f > 0 ? m2 - 1.0f : 1.0f - m2));
    float r = 0, g = 0, b = 0;
    if (hp < 1)      { r = c; g = x; }
    else if (hp < 2) { r = x; g = c; }
    else if (hp < 3) { g = c; b = x; }
    else if (hp < 4) { g = x; b = c; }
    else if (hp < 5) { r = x; b = c; }
    else             { r = c; b = x; }
    float m = v - c;
    unsigned long R = (unsigned long)((r + m) * 255.0f);
    unsigned long G = (unsigned long)((g + m) * 255.0f);
    unsigned long B = (unsigned long)((b + m) * 255.0f);
    return (R << 16) | (G << 8) | B;
}

/* hue at horizontal position u in [0,1): linear blend between anchors */
static float hue_at(float u) {
    float seg = u * (NANCHORS - 1);
    int i = (int)seg;
    if (i >= NANCHORS - 1) i = NANCHORS - 2;
    float f = seg - i;
    float a = ANCHORS[i], b = ANCHORS[i + 1];
    /* take the short way around the wheel */
    float d = b - a;
    if (d > 180.0f) d -= 360.0f;
    if (d < -180.0f) d += 360.0f;
    return wrap360(a + d * f);
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xcolormix: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    char *data = calloc((size_t)sw * sh, 4);
    if (!data) { fprintf(stderr, "xcolormix: oom\n"); return 1; }
    XImage *img = XCreateImage(dpy, DefaultVisual(dpy, scr), (unsigned)depth,
                               ZPixmap, 0, data, (unsigned)sw, (unsigned)sh, 32, 0);
    unsigned long *buf = calloc((size_t)BUF_W * BUF_H, sizeof(unsigned long));
    if (!buf) { fprintf(stderr, "xcolormix: oom\n"); return 1; }

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);

    struct timespec tick = {0, 1000000000L / FPS};
    float t_deg = 0.0f;
    float step = 360.0f / (float)(CYCLE_SEC * FPS);

    while (running && frames != 0) {
        for (int y = 0; y < BUF_H; y++) {
            /* vertical position gently offsets the hue for a diagonal feel */
            float voff = 30.0f * (float)y / (float)BUF_H;
            for (int x = 0; x < BUF_W; x++) {
                float h = wrap360(hue_at((float)x / (float)BUF_W) + t_deg + voff);
                buf[y * BUF_W + x] = hsv_pixel(h, SAT, VAL);
            }
        }
        for (int y = 0; y < sh; y++) {
            int by = y * BUF_H / sh;
            for (int x = 0; x < sw; x++)
                XPutPixel(img, x, y, buf[by * BUF_W + x * BUF_W / sw]);
        }
        XPutImage(dpy, pm, gc, img, 0, 0, 0, 0, (unsigned)sw, (unsigned)sh);
        XChangeProperty(dpy, root, prop_root, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XChangeProperty(dpy, root, prop_eset, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XSetWindowBackgroundPixmap(dpy, root, pm);
        XClearWindow(dpy, root);
        XFlush(dpy);
        t_deg = wrap360(t_deg + step);
        if (frames > 0) frames--;
        nanosleep(&tick, NULL);
    }

    free(buf);
    XDestroyImage(img);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3: Build files** — copy `xmatrix/config.mk`, `Makefile`, `LICENSE`, `.gitignore` with `xmatrix`→`xcolormix`.
- [ ] **Step 4: Verify** — `make -C xcolormix` zero warnings; `make -C xcolormix test` Xvfb skip exit 0; `env -u DISPLAY ./xcolormix/xcolormix -n 3; echo $?` → message + 1; `make -C xcolormix clean`; suite still green (registry test's `available_wallpapers` expectation MUST be updated in the same commit: `"doomfire xmatrix xcolormix "`); sandboxed `./manjaro-sl.sh xcolormix --dry-run --apply --skip-packages` → `selected: xcolormix` (registry picks it up with zero shell edits — that's the payoff assertion; add it as a subprocess test).
- [ ] **Step 5: Commit** — `feat: xcolormix — shifting color gradient wallpaper`

---

### Task 3: xgameoflife

**Files:**
- Create: `xgameoflife/{main.c,config.def.h,config.mk,Makefile,LICENSE,.gitignore}`

**Interfaces:**
- Produces: `xgameoflife` binary; `-n N`; no-display exit 1 with `xgameoflife: cannot open display`.

- [ ] **Step 1: `xgameoflife/config.def.h`** (verbatim)

```c
/* xgameoflife configuration — copy to config.h and edit, suckless-style */

/* generations per second */
static const int FPS = 10;

/* cell size in pixels */
static const int CELL = 8;

/* fraction of cells alive after (re)seeding */
static const double SEED_DENSITY = 0.25;

/* reseed after this many generations without population change
 * (catches death, still lifes, and period-2 oscillator lock) */
static const int STALE_GENS = 120;

/* colors, 0xRRGGBB */
static const unsigned long ALIVE_COLOR = 0x00cc44;
static const unsigned long DEAD_COLOR  = 0x0a0a0a;
```

- [ ] **Step 2: `xgameoflife/main.c`** (verbatim)

```c
/* xgameoflife — Conway's Game of Life on the X11 root window.
 * Toroidal grid, B3/S23, auto-reseed when stagnant. libX11 only. */
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

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static void seed(unsigned char *grid, int n) {
    for (int i = 0; i < n; i++)
        grid[i] = ((double)rand() / RAND_MAX) < SEED_DENSITY;
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xgameoflife: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    int cols = sw / CELL, rows = sh / CELL;
    if (cols < 3) cols = 3;
    if (rows < 3) rows = 3;
    int n = cols * rows;

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    unsigned char *cur = malloc((size_t)n), *next = malloc((size_t)n);
    if (!cur || !next) { fprintf(stderr, "xgameoflife: oom\n"); return 1; }

    srand((unsigned)time(NULL));
    seed(cur, n);
    int last_pop = -1, stale = 0;

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};

    while (running && frames != 0) {
        /* draw current generation */
        XSetForeground(dpy, gc, DEAD_COLOR);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);
        XSetForeground(dpy, gc, ALIVE_COLOR);
        for (int r = 0; r < rows; r++)
            for (int c = 0; c < cols; c++)
                if (cur[r * cols + c])
                    XFillRectangle(dpy, pm, gc, c * CELL, r * CELL,
                                   (unsigned)(CELL - 1), (unsigned)(CELL - 1));
        XChangeProperty(dpy, root, prop_root, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XChangeProperty(dpy, root, prop_eset, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XSetWindowBackgroundPixmap(dpy, root, pm);
        XClearWindow(dpy, root);
        XFlush(dpy);

        /* step: B3/S23 on a torus */
        int pop = 0;
        for (int r = 0; r < rows; r++) {
            int rm = (r + rows - 1) % rows, rp = (r + 1) % rows;
            for (int c = 0; c < cols; c++) {
                int cm = (c + cols - 1) % cols, cp = (c + 1) % cols;
                int nb = cur[rm * cols + cm] + cur[rm * cols + c] + cur[rm * cols + cp]
                       + cur[r  * cols + cm]                      + cur[r  * cols + cp]
                       + cur[rp * cols + cm] + cur[rp * cols + c] + cur[rp * cols + cp];
                unsigned char alive = cur[r * cols + c] ? (nb == 2 || nb == 3)
                                                        : (nb == 3);
                next[r * cols + c] = alive;
                pop += alive;
            }
        }
        unsigned char *tmp = cur; cur = next; next = tmp;

        /* stagnation: dead board, or unchanged population for STALE_GENS
         * generations (catches still lifes and period-2 blinker lock) */
        if (pop == 0) stale = STALE_GENS;
        else if (pop == last_pop) stale++;
        else stale = 0;
        last_pop = pop;
        if (stale >= STALE_GENS) { seed(cur, n); stale = 0; last_pop = -1; }

        if (frames > 0) frames--;
        nanosleep(&tick, NULL);
    }

    free(cur);
    free(next);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3: Build files** from xmatrix's, `xmatrix`→`xgameoflife`.
- [ ] **Step 4: Verify** (same matrix as Task 2; update the registry `available_wallpapers` expected string again; add the positional subprocess test for xgameoflife).
- [ ] **Step 5: Commit** — `feat: xgameoflife — Conway's Game of Life wallpaper`

---

### Task 4: xblackhole

**Files:**
- Create: `xblackhole/{main.c,config.def.h,config.mk,Makefile,LICENSE,.gitignore}`

**Interfaces:**
- Produces: `xblackhole` binary; `-n N`; no-display exit 1 with `xblackhole: cannot open display`.

- [ ] **Step 1: `xblackhole/config.def.h`** (verbatim)

```c
/* xblackhole configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* orbiting particles */
static const int NPARTICLES = 600;

/* event-horizon radius as a fraction of min(width,height)/2 */
static const float HOLE_FRAC = 0.12f;

/* per-frame rotation matrix constants: cos/sin of the swirl angle step.
 * Defaults correspond to ~1.15 degrees/frame (~0.02 rad). */
static const float ROT_C = 0.99980f;
static const float ROT_S = 0.02000f;

/* per-frame radial decay (fraction of radius kept each frame) */
static const float DECAY = 0.9985f;

/* accretion-disk color ramp, inner (hot) to outer (cool), 0xRRGGBB.
 * Blue alternative: { 0xf0f8ff, 0xa0c8ff, 0x5080e0, 0x203070, 0x101838 } */
static const unsigned long RAMP[] = {
    0xfff2d0, 0xffc060, 0xff8020, 0xa03808, 0x401404,
};
```

- [ ] **Step 2: `xblackhole/main.c`** (verbatim)

```c
/* xblackhole — accretion-disk swirl around a central void on the X11 root
 * window. No trig at runtime: per-frame rotation uses the precomputed
 * ROT_C/ROT_S matrix, respawn positions come from rejection sampling, and
 * brightness uses squared radii — libX11 only, no libm. */
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

#define NRAMP ((int)(sizeof(RAMP) / sizeof(RAMP[0])))

typedef struct { float x, y; } P;

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static float frand(void) { return (float)rand() / (float)RAND_MAX; }

/* random point with hole_r2 <= x^2+y^2 <= outer_r2 (rejection sampling) */
static void spawn(P *p, float outer_r, float hole_r2, float outer_r2) {
    do {
        p->x = (2.0f * frand() - 1.0f) * outer_r;
        p->y = (2.0f * frand() - 1.0f) * outer_r;
    } while (p->x * p->x + p->y * p->y < hole_r2 ||
             p->x * p->x + p->y * p->y > outer_r2);
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xblackhole: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);
    float cx = sw / 2.0f, cy = sh / 2.0f;
    float half = (sw < sh ? sw : sh) / 2.0f;
    float hole_r = half * HOLE_FRAC;
    float outer_r = half * 0.95f;
    float hole_r2 = hole_r * hole_r, outer_r2 = outer_r * outer_r;

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    P *ps = malloc(sizeof(P) * (size_t)NPARTICLES);
    if (!ps) { fprintf(stderr, "xblackhole: oom\n"); return 1; }

    srand((unsigned)time(NULL));
    for (int i = 0; i < NPARTICLES; i++)
        spawn(&ps[i], outer_r, hole_r2, outer_r2);

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};
    unsigned long black = BlackPixel(dpy, scr);

    while (running && frames != 0) {
        XSetForeground(dpy, gc, black);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);
        for (int i = 0; i < NPARTICLES; i++) {
            float ox = ps[i].x, oy = ps[i].y;
            /* rotate + decay */
            ps[i].x = (ox * ROT_C - oy * ROT_S) * DECAY;
            ps[i].y = (ox * ROT_S + oy * ROT_C) * DECAY;
            float r2 = ps[i].x * ps[i].x + ps[i].y * ps[i].y;
            if (r2 < hole_r2) {
                spawn(&ps[i], outer_r, hole_r2, outer_r2);
                continue;
            }
            /* brightness from squared-radius position in the disk:
             * 0 at the horizon (hot end of RAMP), 1 at the rim */
            float t = (r2 - hole_r2) / (outer_r2 - hole_r2);
            int idx = (int)(t * NRAMP);
            if (idx >= NRAMP) idx = NRAMP - 1;
            XSetForeground(dpy, gc, RAMP[idx]);
            XDrawLine(dpy, pm, gc,
                      (int)(cx + ox), (int)(cy + oy),
                      (int)(cx + ps[i].x), (int)(cy + ps[i].y));
        }
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

    free(ps);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3: Build files** from xmatrix's, `xmatrix`→`xblackhole`.
- [ ] **Step 4: Verify** (same matrix; registry expected string update; positional subprocess test for xblackhole).
- [ ] **Step 5: Commit** — `feat: xblackhole — accretion-disk swirl wallpaper`

---

### Task 5: Mapping, unified picker, README

**Files:**
- Modify: `lib/wallpaper.sh`, `manjaro-sl.sh`, `readme.md`, `tests/lib-tests.sh`

**Interfaces:**
- Consumes: everything above.
- Produces: `ly_animation_to_wallpaper` covering doom/matrix/colormix/<gameoflife-token>/blackhole; unified Appearance radiolist including gameoflife; colormix phase-3 msgbox removed.

- [ ] **Step 1: Verify the gameoflife token.** Check what animation value the installed Ly accepts: `grep -iB2 -A2 'animation' /etc/ly/config.ini | head -30` (its comments list valid values on Ly 1.x) — and if inconclusive, the Codeberg config docs. Use the exact token (expected: `gameoflife`; if it differs, use Ly's token everywhere below and note it in the report).
- [ ] **Step 2: Failing tests** (update the existing colormix assertion; add):

```bash
assert_eq "$(ly_animation_to_wallpaper colormix)" "xcolormix"
assert_eq "$(ly_animation_to_wallpaper gameoflife)" "xgameoflife"   # ← Ly token
assert_eq "$(ly_animation_to_wallpaper blackhole)" "xblackhole"
assert_eq "$(ly_animation_to_wallpaper somethingelse)" "none"
```

Plus a unified-picker test in the appearance_menu block style: picking colormix must now set dwm/wallpaper=xcolormix, match_wallpaper=on, and NOT show the phase-3 msgbox (assert output lacks "phase-3").

- [ ] **Step 3: Implement.** `ly_animation_to_wallpaper`: add the three cases (keep default `none`). `appearance_menu`: unified radiolist gains the gameoflife entry (Ly token as the tag, "Game of Life" as the label); remove the colormix stub-notice branch (the generic mapping-returned-none notice logic stays for custom names). Grep for any other colormix-special-casing.
- [ ] **Step 4: README.** Wallpaper section: move xcolormix/xgameoflife/xblackhole from "phase 3" to built (with their config.h knobs); mapping table += three rows; Appearance docs mention gameoflife in the unified list and that Custom…-typed `blackhole` now matches the community login animation with a real desktop counterpart; phase-3 line now lists only xstarfield/xplasma/xrain/xfireflies (coming in the next round).
- [ ] **Step 5: Suite green; `bash -n`; `./manjaro-sl.sh --help` exit 0. Commit** — `feat: complete Ly animation matching — colormix, gameoflife, blackhole`

---

### Task 6: Verification sweep + user checkpoint

- [ ] `bash tests/run-tests.sh` → 0 FAIL.
- [ ] `bash -n manjaro-sl.sh lib/*.sh`.
- [ ] For each of xcolormix xgameoflife xblackhole: `make -C <n>` (zero warnings) && `make -C <n> test` (skip, exit 0) && `env -u DISPLAY ./<n>/<n> -n 3` (exit 1) && `make -C <n> clean`.
- [ ] Sandboxed: `./manjaro-sl.sh --wallpaper xblackhole -y --dry-run` → build line has dwm+xblackhole; `./manjaro-sl.sh xcolormix --dry-run --apply --skip-packages` → selected: xcolormix; `--wallpaper xstarfield` → error exit 1 (plan-2 name not yet available).
- [ ] `git status` clean.
- [ ] Report to the user for the live checkpoint: rebuild+install via the TUI or `./manjaro-sl.sh <name> -y`, then preview each with `xcolormix &` / `xgameoflife &` / `xblackhole &` (`pkill <name>` to stop), and optionally switch Appearance to colormix/gameoflife for a matched login+desktop. Plan 2 starts after their nod.
