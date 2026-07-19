/* xfireflies configuration — copy to config.h and edit, suckless-style */

/* frames per second (fireflies tolerate low FPS well) */
static const int FPS = 20;

/* number of fireflies */
static const int NFLIES = 40;

/* base drift speed, px/frame */
static const float DRIFT = 0.6f;

/* sinusoidal wander amplitude, px/frame */
static const float WANDER = 0.8f;

/* firefly color at full brightness, 0xRRGGBB (warm yellow-green) */
static const unsigned long FLY_COLOR = 0xd8e878;

/* brightness levels for the pulse */
enum { NSHADES = 8 };

/* dot size, px */
static const int DOT = 3;
