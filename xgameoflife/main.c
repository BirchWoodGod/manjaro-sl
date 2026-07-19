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
