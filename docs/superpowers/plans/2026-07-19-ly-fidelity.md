# Ly-Fidelity Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace xcolormix's internals with a faithful pixel port of Ly's ColorMix shader math and xblackhole's internals with an embedded player for the actual ly-community blackhole `.dur` animation — per `docs/superpowers/specs/2026-07-19-ly-fidelity-design.md`.

**Architecture:** Both programs are rewritten in place; nothing outside their directories changes (registry/menus/mapping/tests untouched). xblackhole gains a vendored `.dur`, an ATTRIBUTION file, and a build-time python converter emitting a git-ignored `frames.h`.

**Tech Stack:** C99 + libX11 only (no libm — sine table + bit-hack sqrt), python3 (build-time converter; already a project dependency), existing test runner (292 assertions).

## Global Constraints

- Program contract unchanged: `-n N` flag; `<name>: cannot open display` → exit 1; root pixmap + `_XROOTPMAP_ID`/`ESETROOT_PMAP_ID` + `XSetWindowBackgroundPixmap` + `XClearWindow` per frame; warning-free `-std=c99 -pedantic -Wall -Wextra -Os`; links `-lX11` only; `make test` Xvfb skip.
- Existing shell/tests untouched EXCEPT the new converter fixture test appended to `tests/lib-tests.sh` (Task 2).
- xblackhole must build from a clean checkout: the Makefile generates `frames.h` (git-ignored) from the vendored `.dur` before compiling.
- Suite green at every commit; no sudo; `git status` clean post-commit.

---

### Task 1: xcolormix faithful port

**Files:**
- Rewrite: `xcolormix/main.c`, `xcolormix/config.def.h` (Makefile/config.mk/LICENSE/.gitignore unchanged)

- [ ] **Step 1: `xcolormix/config.def.h`** (verbatim; replaces the old file)

```c
/* xcolormix configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* render buffer, scaled to the screen (warp math is per-pixel; smaller =
 * less CPU) */
static const int BUF_W = 240;
static const int BUF_H = 135;

/* the three mixed colors, 0xRRGGBB — defaults match Ly's colormix
 * (col1 red, col2 blue, col3 black) */
static const unsigned long COL1 = 0xff0000;
static const unsigned long COL2 = 0x0000ff;
static const unsigned long COL3 = 0x000000;

/* time step per frame (Ly uses 0.01) */
static const float TIME_SCALE = 0.01f;
```

- [ ] **Step 2: `xcolormix/main.c`** (verbatim; replaces the old file)

```c
/* xcolormix — faithful pixel port of Ly's ColorMix animation
 * (src/animations/ColorMix.zig in fairyglade/ly): a three-iteration UV
 * feedback warp banded through a 12-entry palette that cycles the three
 * color pairs at four density levels (the pixel analogue of Ly's block
 * characters). sin/cos come from an incremental-rotation lookup table and
 * sqrt from a bit-hack + Newton refinement — libX11 only, no libm. */
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

#define TABSZ 1024
#define TABMASK (TABSZ - 1)
/* cos/sin of 2*pi/1024 as literals — the only "trig" in the program */
#define STEP_C 0.999981175f
#define STEP_S 0.006135885f
#define TWO_PI 6.28318530718f
#define HALF_PI 1.57079632679f
/* radians -> table index */
#define RAD2IDX ((float)TABSZ / TWO_PI)

static float stab[TABSZ];

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

static float sin_t(float a) {
    int idx = (int)(a * RAD2IDX) % TABSZ;
    if (idx < 0) idx += TABSZ;
    return stab[idx];
}

static float cos_t(float a) { return sin_t(a + HALF_PI); }

/* bit-hack initial guess + two Newton iterations; plenty for banding */
static float sqrt_a(float x) {
    if (x <= 0.0f) return 0.0f;
    union { float f; unsigned int i; } u;
    u.f = x;
    u.i = (u.i >> 1) + 0x1fbd1df5u;
    float y = u.f;
    y = 0.5f * (y + x / y);
    y = 0.5f * (y + x / y);
    return y;
}

static float len2(float x, float y) { return sqrt_a(x * x + y * y); }

static float frand(void) { return (float)rand() / (float)RAND_MAX; }

/* mix colB..colA by d in [0,1]: d=1 -> colA (full block), d=0.25 -> mostly
 * colB (light shade) — the pixel analogue of fg-over-bg block characters */
static unsigned long mix_px(unsigned long a, unsigned long b, float d) {
    unsigned long ar = (a >> 16) & 0xff, ag = (a >> 8) & 0xff, ab = a & 0xff;
    unsigned long br = (b >> 16) & 0xff, bg = (b >> 8) & 0xff, bb = b & 0xff;
    unsigned long r = (unsigned long)(ar * d + br * (1.0f - d));
    unsigned long g = (unsigned long)(ag * d + bg * (1.0f - d));
    unsigned long bl = (unsigned long)(ab * d + bb * (1.0f - d));
    return (r << 16) | (g << 8) | bl;
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xcolormix: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    build_sine_table();
    srand((unsigned)time(NULL));
    /* per-run pattern variation, matching Ly */
    float cos_mod = frand() * TWO_PI;
    float sin_mod = frand() * TWO_PI;

    /* 12-entry palette: (col1,col2) (col2,col3) (col3,col1) x four density
     * levels — full/dark/medium/light, Ly's █ ▓ ▒ ░ */
    unsigned long pal[12];
    {
        unsigned long pairs[3][2] = {
            { COL1, COL2 }, { COL2, COL3 }, { COL3, COL1 },
        };
        float dens[4] = { 1.0f, 0.75f, 0.5f, 0.25f };
        for (int p = 0; p < 3; p++)
            for (int k = 0; k < 4; k++)
                pal[p * 4 + k] = mix_px(pairs[p][0], pairs[p][1], dens[k]);
    }

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
    long frame_no = 0;

    while (running && frames != 0) {
        float t = (float)frame_no * TIME_SCALE;
        for (int y = 0; y < BUF_H; y++) {
            for (int x = 0; x < BUF_W; x++) {
                /* uv init: pixel adaptation of Ly's cell version — both
                 * axes normalized by height, x centered and halved to
                 * match the terminal's 2:1 cell aspect handling */
                float ux = (float)(2 * x - BUF_W) / (float)(2 * BUF_H);
                float uy = (float)(2 * y - BUF_H) / (float)BUF_H;
                float u2x = 0.0f, u2y = 0.0f;
                for (int i = 0; i < 3; i++) {
                    float l = len2(ux, uy);
                    u2x += ux + l;
                    u2y += uy + l;
                    ux += 0.5f * cos_t(cos_mod + u2y * 0.2f + t * 0.1f);
                    uy += 0.5f * sin_t(sin_mod + u2x - t * 0.1f);
                    float k = 1.0f * cos_t(ux + uy) - sin_t(ux * 0.7f - uy);
                    ux -= k;
                    uy -= k;
                }
                int idx = (int)(len2(ux, uy) * 5.0f) % 12;
                if (idx < 0) idx = 0;
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
        frame_no++;
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

- [ ] **Step 3: Verify.** `make -C xcolormix clean && make -C xcolormix` → zero warnings; `make -C xcolormix test` → Xvfb skip exit 0; `env -u DISPLAY ./xcolormix/xcolormix -n 3; echo $?` → message + 1; `make -C xcolormix clean`; `bash tests/run-tests.sh` → 292/0 unchanged (no shell edits); `git status` clean after commit.
- [ ] **Step 4: Commit** — `feat: xcolormix — faithful port of Ly's ColorMix warp shader`

---

### Task 2: xblackhole embedded loop player

**Files:**
- Create: `xblackhole/dur2c.py`, `xblackhole/ATTRIBUTION`, `xblackhole/blackhole-smooth-240x67.dur` (vendored binary)
- Rewrite: `xblackhole/main.c`, `xblackhole/config.def.h`, `xblackhole/Makefile`, `xblackhole/.gitignore`
- Modify: `tests/lib-tests.sh` (converter fixture test)

**Interfaces:**
- Produces: `dur2c.py IN.dur OUT.h` — emits `frames.h` defining `enum { FRAME_W, FRAME_H, NFRAMES, NCOLORS }`, `static const unsigned long dur_colors[NCOLORS]` (0xRRGGBB), `static const unsigned char dur_runs[]` (3 bytes per run: count 1-255, density 0-6, color index), `static const unsigned int dur_frame_off[NFRAMES + 1]` (byte offsets into `dur_runs`).

- [ ] **Step 1: Vendor the animation.** The file was already downloaded this session to the scratchpad; otherwise re-fetch:

```bash
cp /tmp/claude-1000/-home-birchwoodgod-github-sl/9ed27aa2-ebaf-42c9-9fed-9a0f59ab86ee/scratchpad/blackhole.dur xblackhole/blackhole-smooth-240x67.dur \
  || curl -sL -A "Mozilla/5.0" "https://codeberg.org/fairyglade/ly-community/raw/branch/main/animations/dur/blackhole-smooth-240x67.dur" -o xblackhole/blackhole-smooth-240x67.dur
file xblackhole/blackhole-smooth-240x67.dur   # → gzip compressed data
```

`xblackhole/ATTRIBUTION` (verbatim):

```
blackhole-smooth-240x67.dur
Source: https://codeberg.org/fairyglade/ly-community
Path:   animations/dur/blackhole-smooth-240x67.dur
License (ly-community):

Copyright (C) 2026 by fairyglade

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

Also set the `artist` field from the file into ATTRIBUTION's second line if non-empty: `zcat xblackhole/blackhole-smooth-240x67.dur | python3 -c 'import json,sys; print(json.load(sys.stdin)["DurMovie"].get("artist",""))'` → add `Artist: <value>` under Source.

- [ ] **Step 2: `xblackhole/dur2c.py`** (verbatim)

```python
#!/usr/bin/env python3
"""dur2c.py IN.dur OUT.h — convert a durdraw .dur (gzipped JSON) into an
RLE C header for the xblackhole loop player. Deterministic output.

Cell model: density 0-6 (' ' . · ░ ▒ ▓ █) +
xterm-256 foreground color, run-length encoded as (count, density,
color-index) byte triples per frame.

NOTE the .dur layout quirk (verified against the real file): frame
"contents" is indexed [row][col] but "colorMap" is indexed [col][row].
"""
import gzip
import json
import sys

DENSITY = {' ': 0, '.': 1, '·': 2, '░': 3, '▒': 4,
           '▓': 5, '█': 6}

CUBE = (0, 95, 135, 175, 215, 255)
BASE16 = (0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080,
          0x008080, 0xc0c0c0, 0x808080, 0xff0000, 0x00ff00, 0xffff00,
          0x0000ff, 0xff00ff, 0x00ffff, 0xffffff)


def xterm_rgb(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        r, g, b = CUBE[n // 36], CUBE[(n // 6) % 6], CUBE[n % 6]
        return (r << 16) | (g << 8) | b
    v = 8 + 10 * (n - 232)
    return (v << 16) | (v << 8) | v


def main(inpath, outpath):
    with gzip.open(inpath, 'rt', encoding='utf-8') as fh:
        movie = json.load(fh)["DurMovie"]
    cols, lines = movie["columns"], movie["lines"]
    frames = movie["frames"]

    used = sorted({cell[0] for f in frames for column in f["colorMap"]
                   for cell in column})
    cindex = {c: i for i, c in enumerate(used)}
    if len(used) > 255:
        sys.exit("dur2c: more than 255 distinct colors")

    runs = bytearray()
    offsets = [0]
    for f in frames:
        contents, cmap = f["contents"], f["colorMap"]
        prev, count = None, 0
        for y in range(lines):
            row = contents[y]
            if not isinstance(row, str):
                row = "".join(row)
            for x in range(cols):
                ch = row[x] if x < len(row) else ' '
                d = DENSITY.get(ch, 6)
                col = cindex[cmap[x][y][0]] if d else 0
                cell = (d, col)
                if cell == prev and count < 255:
                    count += 1
                else:
                    if prev is not None:
                        runs.extend((count, prev[0], prev[1]))
                    prev, count = cell, 1
        runs.extend((count, prev[0], prev[1]))
        offsets.append(len(runs))

    with open(outpath, 'w', encoding='utf-8') as out:
        out.write("/* generated by dur2c.py — do not edit */\n")
        out.write("enum { FRAME_W = %d, FRAME_H = %d, NFRAMES = %d, "
                  "NCOLORS = %d };\n" % (cols, lines, len(frames), len(used)))
        out.write("static const unsigned long dur_colors[NCOLORS] = {\n")
        for c in used:
            out.write("    0x%06x,\n" % xterm_rgb(c))
        out.write("};\n")
        out.write("static const unsigned char dur_runs[] = {\n")
        for i in range(0, len(runs), 12):
            out.write("    " + ",".join(str(b) for b in runs[i:i + 12]) + ",\n")
        out.write("};\n")
        out.write("static const unsigned int dur_frame_off[NFRAMES + 1] = "
                  "{ " + ", ".join(str(o) for o in offsets) + " };\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: dur2c.py IN.dur OUT.h")
    main(sys.argv[1], sys.argv[2])
```

- [ ] **Step 3: Converter fixture test (TDD — append to `tests/lib-tests.sh`, run RED before dur2c.py exists):**

```bash
# xblackhole dur2c.py converter: tiny 2-frame 2x2 fixture round-trips into
# expected RLE runs and colors
d2c_tmp=$(mktemp -d)
python3 - "$d2c_tmp" <<'PYEOF'
import gzip, json, sys
fixture = {"DurMovie": {"formatVersion": 7, "colorFormat": "256",
  "encoding": "utf-8", "name": "t", "artist": "t", "framerate": 12.0,
  "columns": 2, "lines": 2, "frames": [
    {"frameNumber": 1, "delay": 0,
     "contents": ["██", "  "],
     "colorMap": [[[17,0],[0,0]], [[17,0],[0,0]]]},
    {"frameNumber": 2, "delay": 0,
     "contents": ["  ", "░░"],
     "colorMap": [[[0,0],[54,0]], [[0,0],[54,0]]]}]}}
with gzip.open(sys.argv[1] + "/fix.dur", "wt", encoding="utf-8") as fh:
    json.dump(fixture, fh)
PYEOF
python3 "$REPO_ROOT/xblackhole/dur2c.py" "$d2c_tmp/fix.dur" "$d2c_tmp/out.h"
assert_ok test -f "$d2c_tmp/out.h"
hdr=$(cat "$d2c_tmp/out.h")
assert_contains "$hdr" "FRAME_W = 2, FRAME_H = 2, NFRAMES = 2"
# colors used: 17 (#00005f) and 54 (#5f0087) — sorted → index 0,1
assert_contains "$hdr" "0x00005f"
assert_contains "$hdr" "0x5f0087"
# frame 1: run of 2 full-density color-0 cells then 2 empty:  2,6,0, 2,0,0
assert_contains "$hdr" "2,6,0"
# frame 2: 2 empty then 2 light-shade color-1:  2,3,1
assert_contains "$hdr" "2,3,1"
rm -rf "$d2c_tmp"
```

(xterm 17 = rgb(0,0,95) = 0x00005f; 54 = rgb(95,0,135) = 0x5f0087 — from the cube formula.)

- [ ] **Step 4: `xblackhole/config.def.h`** (verbatim; replaces old)

```c
/* xblackhole configuration — copy to config.h and edit, suckless-style */

/* playback frames per second; the animation's native rate is 12 —
 * changing this just replays the loop faster or slower */
static const int FPS = 12;

/* global brightness multiplier, 0.0-1.0 */
static const float BRIGHTNESS = 1.0f;
```

- [ ] **Step 5: `xblackhole/main.c`** (verbatim; replaces old)

```c
/* xblackhole — plays the ly-community "blackhole-smooth" durdraw loop on
 * the X11 root window (see ATTRIBUTION). Frames are embedded at build time
 * by dur2c.py as RLE runs of (density, color) cells; density maps to the
 * brightness of the cell's xterm-256-derived RGB. libX11 only. */
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
#include "frames.h"

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

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

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);

    /* precompute pixel per (color, density): density d scales brightness
     * d/6, times the global BRIGHTNESS knob */
    unsigned long px[NCOLORS][7];
    for (int c = 0; c < NCOLORS; c++) {
        unsigned long r = (dur_colors[c] >> 16) & 0xff;
        unsigned long g = (dur_colors[c] >> 8) & 0xff;
        unsigned long b = dur_colors[c] & 0xff;
        for (int d = 0; d < 7; d++) {
            float f = BRIGHTNESS * (float)d / 6.0f;
            px[c][d] = ((unsigned long)(r * f) << 16) |
                       ((unsigned long)(g * f) << 8) |
                       (unsigned long)(b * f);
        }
    }

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};
    unsigned long black = BlackPixel(dpy, scr);
    int frame_no = 0;

    while (running && frames != 0) {
        XSetForeground(dpy, gc, black);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);

        unsigned int off = dur_frame_off[frame_no];
        unsigned int end = dur_frame_off[frame_no + 1];
        int cell = 0;
        while (off < end) {
            int count = dur_runs[off];
            int d = dur_runs[off + 1];
            int col = dur_runs[off + 2];
            off += 3;
            if (d == 0) { cell += count; continue; }
            XSetForeground(dpy, gc, px[col][d]);
            for (int k = 0; k < count; k++, cell++) {
                int cx = cell % FRAME_W, cy = cell / FRAME_W;
                int x0 = cx * sw / FRAME_W, x1 = (cx + 1) * sw / FRAME_W;
                int y0 = cy * sh / FRAME_H, y1 = (cy + 1) * sh / FRAME_H;
                XFillRectangle(dpy, pm, gc, x0, y0,
                               (unsigned)(x1 - x0), (unsigned)(y1 - y0));
            }
        }

        XChangeProperty(dpy, root, prop_root, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XChangeProperty(dpy, root, prop_eset, XA_PIXMAP, 32, PropModeReplace,
                        (unsigned char *)&pm, 1);
        XSetWindowBackgroundPixmap(dpy, root, pm);
        XClearWindow(dpy, root);
        XFlush(dpy);
        frame_no = (frame_no + 1) % NFRAMES;
        if (frames > 0) frames--;
        nanosleep(&tick, NULL);
    }

    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
```

- [ ] **Step 6: `xblackhole/Makefile`** — take the current one and (a) add the generation rule, (b) make the binary depend on `frames.h`, (c) extend `clean`:

```make
frames.h: blackhole-smooth-240x67.dur dur2c.py
	python3 dur2c.py blackhole-smooth-240x67.dur frames.h

xblackhole: main.c config.h frames.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xblackhole frames.h
```

(Keep everything else — `all`, `config.h` rule, `install`/`uninstall`, `test` — exactly as-is.) `.gitignore` gains a `frames.h` line.

- [ ] **Step 7: Verify.** `bash tests/run-tests.sh` → fixture test GREEN, total 296/0 expected (292 + 4 — count precisely); `make -C xblackhole clean && make -C xblackhole` (regenerates frames.h, zero warnings; the generated header is large — if `-pedantic` complains about anything in it, fix the EMITTER in dur2c.py, not the generated file); `make -C xblackhole test` skip exit 0; `env -u DISPLAY ./xblackhole/xblackhole -n 3` → message + 1; `make -C xblackhole clean`; `git status` clean (frames.h ignored, .dur + ATTRIBUTION + dur2c.py tracked).
- [ ] **Step 8: Commit** — `feat: xblackhole — embedded ly-community blackhole loop player`
