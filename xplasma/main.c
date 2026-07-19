/* xplasma — classic demoscene plasma on the X11 root window.
 * The sine table is built by incremental 2D rotation (hardcoded step
 * constants), so no math.h / libm is needed. libX11 only. */
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

#define TABSZ 1024                      /* power of two: cheap wraparound */
#define TABMASK (TABSZ - 1)
#define NPAL 256

/* cos/sin of 2*pi/1024 — the only "trig" in the program, as literals */
#define STEP_C 0.999981175f
#define STEP_S 0.006135885f

static float stab[TABSZ];
static unsigned long pal[NPAL];

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

/* h in [0,360), s/v in [0,1] -> 0xRRGGBB; sector algorithm, no libm */
static unsigned long hsv_pixel(float h, float s, float v) {
    float c = v * s;
    float hp = h / 60.0f;
    float m2 = hp;
    while (m2 >= 2.0f) m2 -= 2.0f;
    float x = c * (1.0f - (m2 - 1.0f > 0 ? m2 - 1.0f : 1.0f - m2));
    float r = 0, g = 0, b = 0;
    if (hp < 1)      { r = c; g = x; }
    else if (hp < 2) { r = x; g = c; }
    else if (hp < 3) { g = c; b = x; }
    else if (hp < 4) { g = x; b = c; }
    else if (hp < 5) { r = x; b = c; }
    else             { r = c; b = x; }
    float m = v - c;
    unsigned long R = (unsigned long)((r + m) * 255.0f);
    unsigned long G = (unsigned long)((g + m) * 255.0f);
    unsigned long B = (unsigned long)((b + m) * 255.0f);
    return (R << 16) | (G << 8) | B;
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xplasma: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

    build_sine_table();
    for (int i = 0; i < NPAL; i++)
        pal[i] = hsv_pixel(360.0f * (float)i / (float)NPAL, SAT, VAL);

    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    unsigned depth = (unsigned)DefaultDepth(dpy, scr);

    Pixmap pm = XCreatePixmap(dpy, root, (unsigned)sw, (unsigned)sh, depth);
    GC gc = XCreateGC(dpy, pm, 0, NULL);
    char *data = calloc((size_t)sw * sh, 4);
    if (!data) { fprintf(stderr, "xplasma: oom\n"); return 1; }
    XImage *img = XCreateImage(dpy, DefaultVisual(dpy, scr), (unsigned)depth,
                               ZPixmap, 0, data, (unsigned)sw, (unsigned)sh, 32, 0);
    unsigned long *buf = calloc((size_t)BUF_W * BUF_H, sizeof(unsigned long));
    if (!buf) { fprintf(stderr, "xplasma: oom\n"); return 1; }

    Atom prop_root = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    struct timespec tick = {0, 1000000000L / FPS};
    int t = 0;

    while (running && frames != 0) {
        for (int y = 0; y < BUF_H; y++) {
            int yi = y * YFREQ + t * TDRIFT2;
            for (int x = 0; x < BUF_W; x++) {
                float v = stab[(x * XFREQ + t * TDRIFT1) & TABMASK]
                        + stab[yi & TABMASK]
                        + stab[((x + y) * DFREQ + t * TDRIFT3) & TABMASK];
                /* v in [-3,3] -> palette index */
                int idx = (int)((v + 3.0f) * (NPAL / 6.0f));
                if (idx < 0) idx = 0;
                if (idx >= NPAL) idx = NPAL - 1;
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
        t++;
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
