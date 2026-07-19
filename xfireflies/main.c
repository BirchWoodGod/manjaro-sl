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
