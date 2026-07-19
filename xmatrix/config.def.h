/* xmatrix configuration — copy to config.h and edit, suckless-style */

/* frames per second (CPU cost scales roughly linearly) */
static const int FPS = 24;

/* glyph cell size in pixels */
static const int CELL_W = 10;
static const int CELL_H = 16;

/* target fraction of columns with an active drop, and per-frame spawn
 * probability for an idle column while below that target */
static const double DENSITY = 0.60;
static const double SPAWN_P = 0.03;

/* X11 core font (no Xft); "fixed" exists everywhere */
static const char FONTNAME[] = "fixed";

/* glyphs cycled at random */
static const char CHARSET[] =
    "abcdefghijklmnopqrstuvwxyz0123456789$+-*/=%\"'#&_(),.;:?!|{}<>[]^~";

/* tail color (16-bit channels) and head color */
static const unsigned short TAIL_R = 0x0000, TAIL_G = 0xffff, TAIL_B = 0x4600;
static const unsigned short HEAD_R = 0xcccc, HEAD_G = 0xffff, HEAD_B = 0xcccc;

/* number of brightness shades in the tail */
enum { NSHADES = 8 };
