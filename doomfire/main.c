/* doomfire — PSX Doom fire on the X11 root window.
 * Algorithm: Fabien Sanglard's "How Doom fire was done" (public domain).
 * Links against libX11 only. MIT licensed. */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "config.h"

static const uint8_t palette[37][3] = {
    {0x07,0x07,0x07},{0x1F,0x07,0x07},{0x2F,0x0F,0x07},{0x47,0x0F,0x07},
    {0x57,0x17,0x07},{0x67,0x1F,0x07},{0x77,0x1F,0x07},{0x8F,0x27,0x07},
    {0x9F,0x2F,0x07},{0xAF,0x3F,0x07},{0xBF,0x47,0x07},{0xC7,0x47,0x07},
    {0xDF,0x4F,0x07},{0xDF,0x57,0x07},{0xDF,0x57,0x07},{0xD7,0x5F,0x07},
    {0xD7,0x5F,0x07},{0xD7,0x67,0x0F},{0xCF,0x6F,0x0F},{0xCF,0x77,0x0F},
    {0xCF,0x7F,0x0F},{0xCF,0x87,0x17},{0xC7,0x87,0x17},{0xC7,0x8F,0x17},
    {0xC7,0x97,0x1F},{0xBF,0x9F,0x1F},{0xBF,0x9F,0x1F},{0xBF,0xA7,0x27},
    {0xBF,0xA7,0x27},{0xBF,0xAF,0x2F},{0xB7,0xAF,0x2F},{0xB7,0xB7,0x2F},
    {0xB7,0xB7,0x37},{0xCF,0xCF,0x6F},{0xDF,0xDF,0x9F},{0xEF,0xEF,0xC7},
    {0xFF,0xFF,0xFF},
};

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static void spread(uint8_t *fire) {
    for (int y = 1; y < FIRE_H; y++) {
        for (int x = 0; x < FIRE_W; x++) {
            int src = y * FIRE_W + x;
            uint8_t p = fire[src];
            if (p == 0) {
                fire[src - FIRE_W] = 0;
            } else {
                int rnd = rand() & 3;
                int dst = src - rnd + 1;
                if (dst < FIRE_W) dst = src;      /* clamp row underflow */
                fire[dst - FIRE_W] = (uint8_t)(p - (rnd & 1));
            }
        }
    }
}

int main(int argc, char *argv[]) {
    int frames = -1;                    /* -1 = run forever */
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);         /* -n N: render N frames and exit (tests) */

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "doomfire: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    int depth = DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, (unsigned)depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    char *data = calloc((size_t)sw * sh, 4);
    if (!data) { fprintf(stderr, "doomfire: oom\n"); return 1; }
    XImage *img = XCreateImage(dpy, DefaultVisual(dpy, scr), (unsigned)depth,
                               ZPixmap, 0, data, (unsigned)sw, (unsigned)sh, 32, 0);

    uint8_t *fire = calloc((size_t)FIRE_W * FIRE_H, 1);
    if (!fire) { fprintf(stderr, "doomfire: oom\n"); return 1; }
    for (int x = 0; x < FIRE_W; x++)
        fire[(FIRE_H - 1) * FIRE_W + x] = 36;   /* white-hot bottom row */

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);

    struct timespec tick = {0, 1000000000L / FPS};
    srand((unsigned)time(NULL));

    while (running && frames != 0) {
        spread(fire);
        /* nearest-neighbor scale fire buffer to screen-size XImage */
        for (int y = 0; y < sh; y++) {
            int fy = y * FIRE_H / sh;
            for (int x = 0; x < sw; x++) {
                int fx = x * FIRE_W / sw;
                const uint8_t *c = palette[fire[fy * FIRE_W + fx]];
                XPutPixel(img, x, y,
                          ((unsigned long)c[0] << 16) |
                          ((unsigned long)c[1] << 8) | c[2]);
            }
        }
        XPutImage(dpy, pm, gc, img, 0, 0, 0, 0, (unsigned)sw, (unsigned)sh);
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

    XDestroyImage(img);                 /* frees data */
    free(fire);
    XFreePixmap(dpy, pm);
    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    return 0;
}
