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
