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
