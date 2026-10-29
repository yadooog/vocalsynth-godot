// Small helpers. Ported from pink-trombone-mod (MIT, Neil Thapen / Christian d'Heureuse).
#pragma once
#include <cmath>
#include <cstdint>
#include <functional>
#include <vector>

namespace pt {

constexpr double PI = 3.14159265358979323846;

inline double clamp(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }
inline double interpolate(double a, double b, double pos) { return a * (1 - pos) + b * pos; }
inline double moveTowards(double current, double target, double up, double down) {
	return current < target ? std::fmin(current + up, target) : std::fmax(current - down, target);
}

// Source of uniform random numbers in [0, 1). Swappable so tests can be deterministic.
double random01();
void setRandomSource(std::function<double()> source);

// Biquad band-pass filter.
class BandPassFilter {
public:
	BandPassFilter(double f0, double q, double sampleRate);
	double process(double x) {
		const double y = nb0 * x + nb1 * x1 + nb2 * x2 - na1 * y1 - na2 * y2;
		x2 = x1; x1 = x; y2 = y1; y1 = y;
		return y;
	}
private:
	double nb0, nb1, nb2, na1, na2;
	double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
};

// White noise from a pre-filled looping buffer, passed through a band-pass filter.
class FilteredNoiseSource {
public:
	FilteredNoiseSource(double f0, double q, double sampleRate, int bufferSize);
	double next() {
		if (pos >= buffer.size()) pos = 0;
		return filter.process(buffer[pos++]);
	}
private:
	std::vector<double> buffer;
	size_t pos = 0;
	BandPassFilter filter;
};

} // namespace pt
