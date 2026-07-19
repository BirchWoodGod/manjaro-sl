/* xmatrix — Matrix-style digital rain on the X11 root window.
 * Same root-pixmap technique as doomfire. libX11 core fonts only.
 * MIT licensed. */
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

typedef struct {
    int active;
    int head;   /* row of the drop's head */
    int len;    /* tail length in cells */
    int speed;  /* advance one row every `speed` frames */
    int tick;
} Drop;

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static unsigned long alloc_shade(Display *dpy, int scr, double f) {
    XColor c;
    c.red   = (unsigned short)(TAIL_R * f);
    c.green = (unsigned short)(TAIL_G * f);
    c.blue  = (unsigned short)(TAIL_B * f);
    c.flags = DoRed | DoGreen | DoBlue;
    if (!XAllocColor(dpy, DefaultColormap(dpy, scr), &c))
        return WhitePixel(dpy, scr);
    return c.pixel;
}

int main(int argc, char *argv[]) {
    int frames = -1;                    /* -1 = run forever */
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);         /* -n N: render N frames and exit */

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xmatrix: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);

    XFontStruct *font = XLoadQueryFont(dpy, FONTNAME);
    if (!font) font = XLoadQueryFont(dpy, "fixed");
    if (!font) font = XLoadQueryFont(dpy, "*");
    if (!font) { fprintf(stderr, "xmatrix: no usable core font\n"); return 1; }
    XSetFont(dpy, gc, font->fid);

    int cols = sw / CELL_W;
    int rows = sh / CELL_H + 1;
    if (cols < 1) cols = 1;
    Drop *drops = calloc((size_t)cols, sizeof(Drop));
    if (!drops) { fprintf(stderr, "xmatrix: oom\n"); return 1; }

    unsigned long shades[NSHADES];
    for (int i = 0; i < NSHADES; i++)
        shades[i] = alloc_shade(dpy, scr, (double)(NSHADES - i) / NSHADES);
    XColor hc;
    hc.red = HEAD_R; hc.green = HEAD_G; hc.blue = HEAD_B;
    hc.flags = DoRed | DoGreen | DoBlue;
    unsigned long head_px = XAllocColor(dpy, DefaultColormap(dpy, scr), &hc)
        ? hc.pixel : WhitePixel(dpy, scr);
    unsigned long black = BlackPixel(dpy, scr);

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);

    struct timespec tickts = {0, 1000000000L / FPS};
    srand((unsigned)time(NULL));
    int charset_n = (int)strlen(CHARSET);

    while (running && frames != 0) {
        /* spawn new drops while below the density target */
        int active = 0;
        for (int c = 0; c < cols; c++) active += drops[c].active;
        for (int c = 0; c < cols && active < (int)(DENSITY * cols); c++) {
            if (!drops[c].active && (double)rand() / RAND_MAX < SPAWN_P) {
                drops[c].active = 1;
                drops[c].head = 0;
                drops[c].len = rows / 4 + rand() % (rows / 2 + 1);
                drops[c].speed = 1 + rand() % 3;
                drops[c].tick = 0;
                active++;
            }
        }

        /* draw the frame */
        XSetForeground(dpy, gc, black);
        XFillRectangle(dpy, pm, gc, 0, 0, (unsigned)sw, (unsigned)sh);
        for (int c = 0; c < cols; c++) {
            if (!drops[c].active) continue;
            for (int i = 0; i < drops[c].len; i++) {
                int row = drops[c].head - i;
                if (row < 0 || row >= rows) continue;
                if (i == 0) XSetForeground(dpy, gc, head_px);
                else XSetForeground(dpy, gc,
                    shades[i * NSHADES / drops[c].len]);
                char g[2] = { CHARSET[rand() % charset_n], 0 };
                XDrawString(dpy, pm, gc, c * CELL_W,
                            row * CELL_H + font->ascent, g, 1);
            }
        }

        /* advance drops */
        for (int c = 0; c < cols; c++) {
            if (!drops[c].active) continue;
            if (++drops[c].tick >= drops[c].speed) {
                drops[c].tick = 0;
                drops[c].head++;
                if (drops[c].head - drops[c].len > rows)
                    drops[c].active = 0;
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
        nanosleep(&tickts, NULL);
    }

    free(drops);
    XFreeFont(dpy, font);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
