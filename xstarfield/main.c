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
