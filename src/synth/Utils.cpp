#include "Utils.h"
#include <random>

namespace pt {

static std::function<double()> g_random;

double random01() {
	if (!g_random) {
		static std::mt19937 rng{ std::random_device{}() };
		static std::uniform_real_distribution<double> dist(0.0, 1.0);
		return dist(rng);
	}
	return g_random();
}

void setRandomSource(std::function<double()> source) { g_random = std::move(source); }

BandPassFilter::BandPassFilter(double f0, double q, double sampleRate) {
	const double w0 = 2 * PI * f0 / sampleRate;
	const double alpha = std::sin(w0) / (2 * q);
	const double b0 = alpha, b1 = 0, b2 = -alpha;
	const double a0 = 1 + alpha, a1 = -2 * std::cos(w0), a2 = 1 - alpha;
	nb0 = b0 / a0; nb1 = b1 / a0; nb2 = b2 / a0;
	na1 = a1 / a0; na2 = a2 / a0;
}

FilteredNoiseSource::FilteredNoiseSource(double f0, double q, double sampleRate, int bufferSize)
		: buffer(bufferSize), filter(f0, q, sampleRate) {
	for (int i = 0; i < bufferSize; i++) buffer[i] = 2 * random01() - 1;
}

} // namespace pt
