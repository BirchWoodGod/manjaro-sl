/* xstarfield configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 30;

/* number of stars */
static const int NSTARS = 400;

/* per-frame depth decrease; higher = faster flight */
static const float SPEED = 0.006f;

/* star color at full brightness, 0xRRGGBB (green alt: 0x00ff46) */
static const unsigned long STAR_COLOR = 0xffffff;

/* number of brightness levels (dimmer when far) */
enum { NSHADES = 6 };
