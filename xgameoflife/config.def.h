/* xgameoflife configuration — copy to config.h and edit, suckless-style */

/* generations per second */
static const int FPS = 10;

/* cell size in pixels */
static const int CELL = 8;

/* fraction of cells alive after (re)seeding */
static const double SEED_DENSITY = 0.25;

/* reseed after this many generations without population change
 * (catches death, still lifes, and period-2 oscillator lock) */
static const int STALE_GENS = 120;

/* colors, 0xRRGGBB */
static const unsigned long ALIVE_COLOR = 0x00cc44;
static const unsigned long DEAD_COLOR  = 0x0a0a0a;
