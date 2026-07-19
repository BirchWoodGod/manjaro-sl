/* xcolormix — slowly shifting color gradients on the X11 root window.
 * Same root-pixmap technique as doomfire. libX11 only, no libm. */
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

#define NANCHORS ((int)(sizeof(ANCHORS) / sizeof(ANCHORS[0])))

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }

static float wrap360(float h) {
    while (h >= 360.0f) h -= 360.0f;
    while (h < 0.0f) h += 360.0f;
    return h;
}

/* h in [0,360), s/v in [0,1] -> 0xRRGGBB. Sector algorithm, no libm. */
static unsigned long hsv_pixel(float h, float s, float v) {
    float c = v * s;
    float hp = h / 60.0f;
    float m2 = hp;                       /* hp mod 2 without fmod */
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

/* hue at horizontal position u in [0,1): linear blend between anchors */
static float hue_at(float u) {
    float seg = u * (NANCHORS - 1);
    int i = (int)seg;
    if (i >= NANCHORS - 1) i = NANCHORS - 2;
    float f = seg - i;
    float a = ANCHORS[i], b = ANCHORS[i + 1];
    /* take the short way around the wheel */
    float d = b - a;
    if (d > 180.0f) d -= 360.0f;
    if (d < -180.0f) d += 360.0f;
    return wrap360(a + d * f);
}

int main(int argc, char *argv[]) {
    int frames = -1;
    if (argc == 3 && strcmp(argv[1], "-n") == 0)
        frames = atoi(argv[2]);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "xcolormix: cannot open display\n"); return 1; }
    signal(SIGINT, stop);
    signal(SIGTERM, stop);

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
    float t_deg = 0.0f;
    float step = 360.0f / (float)(CYCLE_SEC * FPS);

    while (running && frames != 0) {
        for (int y = 0; y < BUF_H; y++) {
            /* vertical position gently offsets the hue for a diagonal feel */
            float voff = 30.0f * (float)y / (float)BUF_H;
            for (int x = 0; x < BUF_W; x++) {
                float h = wrap360(hue_at((float)x / (float)BUF_W) + t_deg + voff);
                buf[y * BUF_W + x] = hsv_pixel(h, SAT, VAL);
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
        t_deg = wrap360(t_deg + step);
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
