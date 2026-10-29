// Simplex noise, used for the natural wobble in pitch and tenseness.
// Based on public domain code by Stefan Gustavson, via pink-trombone-mod.
#pragma once

namespace pt {
void setNoiseSeed(double seed);
double simplex2(double x, double y);
inline double simplex1(double x) { return simplex2(x * 1.2, -x * 0.7); }
} // namespace pt
