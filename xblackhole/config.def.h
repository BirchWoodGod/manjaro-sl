/* xblackhole configuration — copy to config.h and edit, suckless-style */

/* frames per second */
static const int FPS = 24;

/* orbiting particles */
static const int NPARTICLES = 600;

/* event-horizon radius as a fraction of min(width,height)/2 */
static const float HOLE_FRAC = 0.12f;

/* per-frame rotation matrix constants: cos/sin of the swirl angle step.
 * Defaults correspond to ~1.15 degrees/frame (~0.02 rad). */
static const float ROT_C = 0.99980f;
static const float ROT_S = 0.02000f;

/* per-frame radial decay (fraction of radius kept each frame) */
static const float DECAY = 0.9985f;

/* accretion-disk color ramp, inner (hot) to outer (cool), 0xRRGGBB.
 * Blue alternative: { 0xf0f8ff, 0xa0c8ff, 0x5080e0, 0x203070, 0x101838 } */
static const unsigned long RAMP[] = {
    0xfff2d0, 0xffc060, 0xff8020, 0xa03808, 0x401404,
};
