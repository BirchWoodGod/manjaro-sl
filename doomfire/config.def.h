/* doomfire configuration — copy to config.h and edit, suckless-style */

/* frames per second (CPU cost scales roughly linearly) */
static const int FPS = 24;

/* fire simulation buffer size; scaled to the screen with nearest-neighbor.
 * Smaller = chunkier pixels + less CPU. Classic PSX look: 320x168. */
static const int FIRE_W = 320;
static const int FIRE_H = 168;
