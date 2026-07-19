/* xrain configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 30;

/* horizontal spacing between rain columns, px */
static const int COL_W = 6;

/* fraction of columns with an active drop */
static const double DENSITY = 0.35;

/* per-frame spawn probability for an idle column while below the target */
static const double SPAWN_P = 0.05;

/* fall speed range, px/frame */
static const int SPEED_MIN = 8;
static const int SPEED_MAX = 18;

/* streak length range, px */
static const int LEN_MIN = 10;
static const int LEN_MAX = 28;

/* draw a 2-frame splash tick when a drop hits the bottom (0 = off) */
static const int SPLASH = 1;

/* streak colors by speed (slow -> fast), 0xRRGGBB blue-grey ramp */
static const unsigned long RAMP[] = { 0x4a5a6a, 0x6a7f95, 0x8fa8c0 };
