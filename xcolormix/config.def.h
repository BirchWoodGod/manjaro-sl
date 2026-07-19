/* xcolormix configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* render buffer, scaled to the screen (smaller = less CPU) */
static const int BUF_W = 320;
static const int BUF_H = 180;

/* anchor hues (degrees, 0-360) blended left-to-right across the screen;
 * the whole palette also rotates one full wheel every CYCLE_SEC seconds */
static const float ANCHORS[] = { 200.0f, 280.0f, 340.0f, 40.0f };
static const int CYCLE_SEC = 60;

/* saturation and value, 0..1 */
static const float SAT = 0.85f;
static const float VAL = 0.55f;
