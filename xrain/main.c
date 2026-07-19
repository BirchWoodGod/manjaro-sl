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
