/* xplasma configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* render buffer, scaled to the screen */
static const int BUF_W = 320;
static const int BUF_H = 180;

/* wave frequencies: table steps per buffer pixel (x, y, diagonal) and per
 * frame (three independent time drifts) — bigger = busier */
static const int XFREQ = 12;
static const int YFREQ = 16;
static const int DFREQ = 7;
static const int TDRIFT1 = 5;
static const int TDRIFT2 = 3;
static const int TDRIFT3 = 2;

/* palette saturation/value, 0..1 (hue cycles the full wheel) */
static const float SAT = 0.80f;
static const float VAL = 0.60f;
