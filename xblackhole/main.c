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
