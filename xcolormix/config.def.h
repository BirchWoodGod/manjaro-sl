/* xcolormix configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* render buffer, scaled to the screen (warp math is per-pixel; smaller =
 * less CPU) */
static const int BUF_W = 240;
static const int BUF_H = 135;

/* the three mixed colors, 0xRRGGBB — defaults match Ly's colormix
 * (col1 red, col2 blue, col3 black) */
static const unsigned long COL1 = 0xff0000;
static const unsigned long COL2 = 0x0000ff;
static const unsigned long COL3 = 0x000000;

/* time step per frame (Ly uses 0.01) */
static const float TIME_SCALE = 0.01f;
