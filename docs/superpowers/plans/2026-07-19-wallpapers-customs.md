# Wallpapers Plan 2: Custom Four Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship xstarfield, xplasma, xrain, and xfireflies — the first custom (non-Ly-matching) desktop wallpapers — per `docs/superpowers/specs/2026-07-19-wallpapers-phase3-design.md` §3.

**Architecture:** Four standalone suckless-C dirs on the proven template. Registry entries already exist, so each program surfaces automatically in the Desktop-wallpaper override list, `--wallpaper`, positional components, and cleanup the moment its directory lands. No mapping changes (customs have no Ly counterpart — `ly_animation_to_wallpaper` untouched).

**Tech Stack:** C99 + libX11 ONLY (no libm — sine effects use incremental-rotation lookup tables), bash test runner (264 assertions).

## Global Constraints

- Per program: `main.c`, `config.def.h`, `config.mk`/`Makefile`/`LICENSE`/`.gitignore` copied from `xmatrix/` with name substitution (keep `-D_POSIX_C_SOURCE=200809L` + `;`-joined Xvfb test recipe); `-n N` flag; `<name>: cannot open display` → exit 1; root pixmap + `_XROOTPMAP_ID`/`ESETROOT_PMAP_ID` + `XSetWindowBackgroundPixmap` + `XClearWindow` per frame; warning-free `-std=c99 -pedantic -Wall -Wextra -Os`; links `-lX11` only.
- Per task test edits (same pattern as the Ly-trio tasks): update the registry `available_wallpapers` expected string (append the new name in REGISTRY order — note the registry order is `… xblackhole xstarfield xplasma xrain xfireflies`), and add the sandboxed positional subprocess test (`./manjaro-sl.sh <name> --dry-run --apply --skip-packages` → exit 0, `selected: <name>`; 2 assertions).
- Suite green at every commit; bash -n where shell files change; no sudo; Xvfb absent (make test skip = expected).

---

### Task 1: xstarfield

**Files:** Create `xstarfield/{main.c,config.def.h,config.mk,Makefile,LICENSE,.gitignore}`; modify `tests/lib-tests.sh`.

- [ ] **Step 1: `xstarfield/config.def.h`** (verbatim)

```c
/* xstarfield configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 30;

/* number of stars */
static const int NSTARS = 400;

/* per-frame depth decrease; higher = faster flight */
static const float SPEED = 0.006f;

/* star color at full brightness, 0xRRGGBB (green alt: 0x00ff46) */
static const unsigned long STAR_COLOR = 0xffffff;

/* number of brightness levels (dimmer when far) */
enum { NSHADES = 6 };
```

- [ ] **Step 2: `xstarfield/main.c`** (verbatim)

```c
/* xstarfield — flying-through-space starfield on the X11 root window.
 * Perspective projection is plain division; no trig, no libm. */
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

typedef struct { float x, y, z; } Star;

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static float frand(void) { return (float)rand() / (float)RAND_MAX; }

static void spawn(Star *s, int deep) {
    s->x = 2.0f * frand() - 1.0f;
    s->y = 2.0f * frand() - 1.0f;
    /* deep spawn on init spreads stars through the volume; respawns start
     * at the back so they fly the whole way */
    s->z = deep ? (0.05f + 0.95f * frand()) : 1.0f;
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xstarfield: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);
    float cx = sw / 2.0f, cy = sh / 2.0f;

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    Star *stars = malloc(sizeof(Star) * (size_t)NSTARS);
    if (!stars) { fprintf(stderr, "xstarfield: oom\n"); return 1; }

    srand((unsigned)time(NULL));
    for (int i = 0; i < NSTARS; i++) spawn(&stars[i], 1);

    /* precompute shade pixels: STAR_COLOR scaled by (level+1)/NSHADES */
    unsigned long shades[NSHADES];
    for (int i = 0; i < NSHADES; i++) {
        unsigned long r = (STAR_COLOR >> 16) & 0xff;
        unsigned long g = (STAR_COLOR >> 8) & 0xff;
        unsigned long b = STAR_COLOR & 0xff;
        unsigned long f = (unsigned long)(i + 1);
        shades[i] = ((r * f / NSHADES) << 16) |
                    ((g * f / NSHADES) << 8) |
                    (b * f / NSHADES);
    }

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};
    unsigned long black = BlackPixel(dpy, scr);

    while (running && frames != 0) {
        XSetForeground(dpy, gc, black);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);
        for (int i = 0; i < NSTARS; i++) {
            float zo = stars[i].z;
            stars[i].z -= SPEED;
            float zn = stars[i].z;
            if (zn <= SPEED) { spawn(&stars[i], 0); continue; }
            /* project old and new positions; streak between them */
            int pxo = (int)(cx + stars[i].x / zo * cx);
            int pyo = (int)(cy + stars[i].y / zo * cy);
            int pxn = (int)(cx + stars[i].x / zn * cx);
            int pyn = (int)(cy + stars[i].y / zn * cy);
            if (pxn < 0 || pxn >= sw || pyn < 0 || pyn >= sh) {
                spawn(&stars[i], 0);
                continue;
            }
            int lvl = (int)((1.0f - zn) * NSHADES);
            if (lvl >= NSHADES) lvl = NSHADES - 1;
            if (lvl < 0) lvl = 0;
            XSetForeground(dpy, gc, shades[lvl]);
            XDrawLine(dpy, pm, gc, pxo, pyo, pxn, pyn);
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

    free(stars);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3:** Build files from `xmatrix/` (`xmatrix`→`xstarfield`).
- [ ] **Step 4: Tests (TDD — RED before the dir exists):** registry string → `"doomfire xmatrix xcolormix xgameoflife xblackhole xstarfield "`; positional subprocess test for xstarfield.
- [ ] **Step 5: Verify:** `make -C xstarfield` zero warnings; `make -C xstarfield test` skip exit 0; `env -u DISPLAY ./xstarfield/xstarfield -n 3` → message + exit 1; `make -C xstarfield clean`; suite 266/0 expected (264+2); `git status` clean post-commit.
- [ ] **Step 6: Commit** — `feat: xstarfield — flying starfield wallpaper`

---

### Task 2: xplasma

**Files:** Create `xplasma/{main.c,config.def.h,config.mk,Makefile,LICENSE,.gitignore}`; modify `tests/lib-tests.sh`.

- [ ] **Step 1: `xplasma/config.def.h`** (verbatim)

```c
/* xplasma configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* render buffer, scaled to the screen */
static const int BUF_W = 320;
static const int BUF_H = 180;

/* wave frequencies: table steps per buffer pixel (x, y, diagonal) and per
 * frame (three independent time drifts) — bigger = busier */
static const int XFREQ = 12;
static const int YFREQ = 16;
static const int DFREQ = 7;
static const int TDRIFT1 = 5;
static const int TDRIFT2 = 3;
static const int TDRIFT3 = 2;

/* palette saturation/value, 0..1 (hue cycles the full wheel) */
static const float SAT = 0.80f;
static const float VAL = 0.60f;
```

- [ ] **Step 2: `xplasma/main.c`** (verbatim)

```c
/* xplasma — classic demoscene plasma on the X11 root window.
 * The sine table is built by incremental 2D rotation (hardcoded step
 * constants), so no math.h / libm is needed. libX11 only. */
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

#define TABSZ 1024                      /* power of two: cheap wraparound */
#define TABMASK (TABSZ - 1)
#define NPAL 256

/* cos/sin of 2*pi/1024 — the only "trig" in the program, as literals */
#define STEP_C 0.999981175f
#define STEP_S 0.006135885f

static float stab[TABSZ];
static unsigned long pal[NPAL];

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static void build_sine_table(void) {
    float s = 0.0f, c = 1.0f;
    for (int i = 0; i < TABSZ; i++) {
        stab[i] = s;
        float ns = s * STEP_C + c * STEP_S;
        float nc = c * STEP_C - s * STEP_S;
        s = ns; c = nc;
    }
}

/* h in [0,360), s/v in [0,1] -> 0xRRGGBB; sector algorithm, no libm */
static unsigned long hsv_pixel(float h, float s, float v) {
    float c = v * s;
    float hp = h / 60.0f;
    float m2 = hp;
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

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xplasma: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    build_sine_table();
    for (int i = 0; i < NPAL; i++)
        pal[i] = hsv_pixel(360.0f * (float)i / (float)NPAL, SAT, VAL);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    char *data = calloc((size_t)sw * sh, 4);
    if (!data) { fprintf(stderr, "xplasma: oom\n"); return 1; }
    XImage *img = XCreateImage(dpy, DefaultVisual(dpy, scr), (unsigned)depth,
                               ZPixmap, 0, data, (unsigned)sw, (unsigned)sh, 32, 0);
    unsigned long *buf = calloc((size_t)BUF_W * BUF_H, sizeof(unsigned long));
    if (!buf) { fprintf(stderr, "xplasma: oom\n"); return 1; }

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};
    int t = 0;

    while (running && frames != 0) {
        for (int y = 0; y < BUF_H; y++) {
            int yi = y * YFREQ + t * TDRIFT2;
            for (int x = 0; x < BUF_W; x++) {
                float v = stab[(x * XFREQ + t * TDRIFT1) & TABMASK]
                        + stab[yi & TABMASK]
                        + stab[((x + y) * DFREQ + t * TDRIFT3) & TABMASK];
                /* v in [-3,3] -> palette index */
                int idx = (int)((v + 3.0f) * (NPAL / 6.0f));
                if (idx < 0) idx = 0;
                if (idx >= NPAL) idx = NPAL - 1;
                buf[y * BUF_W + x] = pal[idx];
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
        t++;
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

- [ ] **Step 3:** Build files (`xmatrix`→`xplasma`).
- [ ] **Step 4: Tests:** registry string += `xplasma `; positional subprocess test.
- [ ] **Step 5: Verify** (same matrix; suite 268/0 expected).
- [ ] **Step 6: Commit** — `feat: xplasma — demoscene plasma wallpaper`

---

### Task 3: xrain

**Files:** Create `xrain/{main.c,config.def.h,config.mk,Makefile,LICENSE,.gitignore}`; modify `tests/lib-tests.sh`.

- [ ] **Step 1: `xrain/config.def.h`** (verbatim)

```c
/* xrain configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 30;

/* horizontal spacing between rain columns, px */
static const int COL_W = 6;

/* fraction of columns with an active drop */
static const double DENSITY = 0.35;

/* per-frame spawn probability for an idle column while below the target */
static const double SPAWN_P = 0.05;

/* fall speed range, px/frame */
static const int SPEED_MIN = 8;
static const int SPEED_MAX = 18;

/* streak length range, px */
static const int LEN_MIN = 10;
static const int LEN_MAX = 28;

/* draw a 2-frame splash tick when a drop hits the bottom (0 = off) */
static const int SPLASH = 1;

/* streak colors by speed (slow -> fast), 0xRRGGBB blue-grey ramp */
static const unsigned long RAMP[] = { 0x4a5a6a, 0x6a7f95, 0x8fa8c0 };
```

- [ ] **Step 2: `xrain/main.c`** (verbatim)

```c
/* xrain — falling rain streaks on the X11 root window. xmatrix's column
 * engine with line primitives instead of glyphs. libX11 only, no libm. */
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

typedef struct {
    int active;
    int y;       /* head position, px */
    int speed;   /* px per frame */
    int len;     /* streak length, px */
    int splash;  /* frames of splash left after landing */
} Drop;

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xrain: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    int cols = sw / COL_W;
    if (cols < 1) cols = 1;
    Drop *drops = calloc((size_t)cols, sizeof(Drop));
    if (!drops) { fprintf(stderr, "xrain: oom\n"); return 1; }

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);

    srand((unsigned)time(NULL));

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};
    unsigned long black = BlackPixel(dpy, scr);

    while (running && frames != 0) {
        /* spawn while below target density */
        int active = 0;
        for (int c = 0; c < cols; c++) active += drops[c].active;
        for (int c = 0; c < cols && active < (int)(DENSITY * cols); c++) {
            if (!drops[c].active && !drops[c].splash &&
                (double)rand() / RAND_MAX < SPAWN_P) {
                drops[c].active = 1;
                drops[c].y = 0;
                drops[c].speed = SPEED_MIN + rand() % (SPEED_MAX - SPEED_MIN + 1);
                drops[c].len = LEN_MIN + rand() % (LEN_MAX - LEN_MIN + 1);
                active++;
            }
        }

        XSetForeground(dpy, gc, black);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);
        for (int c = 0; c < cols; c++) {
            int x = c * COL_W + COL_W / 2;
            if (drops[c].active) {
                int shade = (drops[c].speed - SPEED_MIN) * NRAMP
                            / (SPEED_MAX - SPEED_MIN + 1);
                if (shade >= NRAMP) shade = NRAMP - 1;
                XSetForeground(dpy, gc, RAMP[shade]);
                int top = drops[c].y - drops[c].len;
                if (top < 0) top = 0;
                XDrawLine(dpy, pm, gc, x, top, x, drops[c].y);
                drops[c].y += drops[c].speed;
                if (drops[c].y - drops[c].len > sh) {
                    drops[c].active = 0;
                    drops[c].splash = SPLASH ? 2 : 0;
                }
            } else if (drops[c].splash > 0) {
                XSetForeground(dpy, gc, RAMP[NRAMP - 1]);
                XDrawLine(dpy, pm, gc, x - 3, sh - 2, x + 3, sh - 2);
                drops[c].splash--;
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
        nanosleep(&tick, NULL);
    }

    free(drops);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3:** Build files (`xmatrix`→`xrain`).
- [ ] **Step 4: Tests:** registry string += `xrain `; positional subprocess test.
- [ ] **Step 5: Verify** (same matrix; suite 270/0 expected).
- [ ] **Step 6: Commit** — `feat: xrain — falling rain wallpaper`

---

### Task 4: xfireflies

**Files:** Create `xfireflies/{main.c,config.def.h,config.mk,Makefile,LICENSE,.gitignore}`; modify `tests/lib-tests.sh`.

- [ ] **Step 1: `xfireflies/config.def.h`** (verbatim)

```c
/* xfireflies configuration — copy to config.h and edit, suckless-style */

/* frames per second (fireflies tolerate low FPS well) */
static const int FPS = 20;

/* number of fireflies */
static const int NFLIES = 40;

/* base drift speed, px/frame */
static const float DRIFT = 0.6f;

/* sinusoidal wander amplitude, px/frame */
static const float WANDER = 0.8f;

/* firefly color at full brightness, 0xRRGGBB (warm yellow-green) */
static const unsigned long FLY_COLOR = 0xd8e878;

/* brightness levels for the pulse */
enum { NSHADES = 8 };

/* dot size, px */
static const int DOT = 3;
```

- [ ] **Step 2: `xfireflies/main.c`** (verbatim)

```c
/* xfireflies — drifting, pulsing fireflies on the X11 root window.
 * Wander and pulse phases index a sine table built by incremental
 * rotation (hardcoded step constants) — no math.h / libm. libX11 only. */
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

#define TABSZ 256
#define TABMASK (TABSZ - 1)
/* cos/sin of 2*pi/256 as literals — the only "trig" in the program */
#define STEP_C 0.999698819f
#define STEP_S 0.024541229f

typedef struct {
    float x, y;      /* position, px */
    float vx, vy;    /* constant drift, px/frame */
    int wphase;      /* wander phase index into stab */
    int wstride;     /* wander phase advance per frame */
    int pphase;      /* pulse phase index */
    int pstride;     /* pulse phase advance per frame */
} Fly;

static float stab[TABSZ];

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static float frand(void) { return (float)rand() / (float)RAND_MAX; }

static void build_sine_table(void) {
    float s = 0.0f, c = 1.0f;
    for (int i = 0; i < TABSZ; i++) {
        stab[i] = s;
        float ns = s * STEP_C + c * STEP_S;
        float nc = c * STEP_C - s * STEP_S;
        s = ns; c = nc;
    }
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xfireflies: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    build_sine_table();

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    Fly *flies = malloc(sizeof(Fly) * (size_t)NFLIES);
    if (!flies) { fprintf(stderr, "xfireflies: oom\n"); return 1; }

    srand((unsigned)time(NULL));
    for (int i = 0; i < NFLIES; i++) {
        flies[i].x = frand() * (float)sw;
        flies[i].y = frand() * (float)sh;
        flies[i].vx = (2.0f * frand() - 1.0f) * DRIFT;
        flies[i].vy = (2.0f * frand() - 1.0f) * DRIFT;
        flies[i].wphase = rand() & TABMASK;
        flies[i].wstride = 1 + rand() % 3;
        flies[i].pphase = rand() & TABMASK;
        flies[i].pstride = 1 + rand() % 2;
    }

    /* precompute pulse shades of FLY_COLOR */
    unsigned long shades[NSHADES];
    for (int i = 0; i < NSHADES; i++) {
        unsigned long r = (FLY_COLOR >> 16) & 0xff;
        unsigned long g = (FLY_COLOR >> 8) & 0xff;
        unsigned long b = FLY_COLOR & 0xff;
        unsigned long f = (unsigned long)(i + 1);
        shades[i] = ((r * f / NSHADES) << 16) |
                    ((g * f / NSHADES) << 8) |
                    (b * f / NSHADES);
    }

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};
    unsigned long black = BlackPixel(dpy, scr);

    while (running && frames != 0) {
        XSetForeground(dpy, gc, black);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);
        for (int i = 0; i < NFLIES; i++) {
            Fly *f = &flies[i];
            f->wphase = (f->wphase + f->wstride) & TABMASK;
            f->pphase = (f->pphase + f->pstride) & TABMASK;
            /* wander: sine on x, cosine (sine + quarter turn) on y */
            f->x += f->vx + stab[f->wphase] * WANDER;
            f->y += f->vy + stab[(f->wphase + TABSZ / 4) & TABMASK] * WANDER;
            /* wrap at edges */
            if (f->x < 0) f->x += (float)sw;
            if (f->x >= (float)sw) f->x -= (float)sw;
            if (f->y < 0) f->y += (float)sh;
            if (f->y >= (float)sh) f->y -= (float)sh;
            /* pulse brightness: stab in [-1,1] -> [0, NSHADES) */
            int lvl = (int)((stab[f->pphase] + 1.0f) * 0.5f * NSHADES);
            if (lvl >= NSHADES) lvl = NSHADES - 1;
            if (lvl < 0) lvl = 0;
            XSetForeground(dpy, gc, shades[lvl]);
            XFillRectangle(dpy, pm, gc, (int)f->x, (int)f->y,
                           (unsigned)DOT, (unsigned)DOT);
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

    free(flies);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 3:** Build files (`xmatrix`→`xfireflies`).
- [ ] **Step 4: Tests:** registry string += `xfireflies ` (full: `"doomfire xmatrix xcolormix xgameoflife xblackhole xstarfield xplasma xrain xfireflies "`); positional subprocess test.
- [ ] **Step 5: Verify** (same matrix; suite 272/0 expected).
- [ ] **Step 6: Commit** — `feat: xfireflies — drifting fireflies wallpaper`

---

### Task 5: README + verification sweep

**Files:** Modify `readme.md`.

- [ ] **Step 1: README.** Wallpaper section: the four customs move from "phase 3 / coming" to built, each with its real `config.def.h` knobs (read the files); note they are desktop-only (no Ly counterpart — selectable via Appearance → Desktop wallpaper override, `--wallpaper`, or as components); remove any remaining "phase 3" list (it's now empty — say future wallpapers are welcome, registry makes them one-directory additions).
- [ ] **Step 2: Accuracy pass.** `./manjaro-sl.sh --help` — the shipped-wallpaper regression test updates itself via `available_wallpapers`, but confirm the usage() text's parenthetical wallpaper list includes all nine (grep; the help-coverage test in tests/lib-tests.sh will catch it — run the suite).
- [ ] **Step 3: Full matrix.** Suite 0 FAIL; `bash -n manjaro-sl.sh lib/*.sh`; all four new programs: build warning-free + test-skip + no-display exit 1 + clean; sandboxed `./manjaro-sl.sh --wallpaper xfireflies -y --dry-run` → build line has dwm+xfireflies; `git status` clean.
- [ ] **Step 4: Commit** — `docs: README for the four custom wallpapers`
