#include "Tract.h"
#include <cmath>

namespace pt {

Tract::Tract(Glottis &glottis_, double tractSampleRate_)
		: glottis(glottis_), tractSampleRate(tractSampleRate_),
		  fricationNoise(1000, 0.5, tractSampleRate_, 0x8000) {}

void Tract::calculateNoseReflections() {
	double a[noseLength];
	for (int i = 0; i < noseLength; i++) {
		a[i] = std::fmax(1E-6, noseDiameter[i] * noseDiameter[i]);
	}
	for (int i = 1; i < noseLength; i++) {
		noseReflection[i] = (a[i - 1] - a[i]) / (a[i - 1] + a[i]);
	}
}

void Tract::calculateNewBlockParameters() {
	calculateMainTractReflections();
	calculateNoseJunctionReflections();
}

void Tract::calculateMainTractReflections() {
	double a[n];
	for (int i = 0; i < n; i++) {
		a[i] = diameter[i] * diameter[i];
	}
	for (int i = 1; i < n; i++) {
		reflection[i] = newReflection[i];
		const double sum = a[i - 1] + a[i];
		newReflection[i] = (std::fabs(sum) > 1E-6) ? (a[i - 1] - a[i]) / sum : 1;
	}
}

void Tract::calculateNoseJunctionReflections() {
	reflectionLeft = newReflectionLeft;
	reflectionRight = newReflectionRight;
	reflectionNose = newReflectionNose;
	const double velumA = noseDiameter[0] * noseDiameter[0];
	const double an0 = diameter[noseStart] * diameter[noseStart];
	const double an1 = diameter[noseStart + 1] * diameter[noseStart + 1];
	const double sum = an0 + an1 + velumA;
	const bool ok = std::fabs(sum) > 1E-6;
	newReflectionLeft = ok ? (2 * an0 - sum) / sum : 1;
	newReflectionRight = ok ? (2 * an1 - sum) / sum : 1;
	newReflectionNose = ok ? (2 * velumA - sum) / sum : 1;
}

double Tract::step(double glottalOutput, double lambda) {
	// mouth
	processTransients();
	addTurbulenceNoise();

	junctionOutputRight[0] = left[0] * glottalReflection + glottalOutput;
	junctionOutputLeft[n] = right[n - 1] * lipReflection;

	for (int i = 1; i < n; i++) {
		const double r = interpolate(reflection[i], newReflection[i], lambda);
		const double w = r * (right[i - 1] + left[i]);
		junctionOutputRight[i] = right[i - 1] - w;
		junctionOutputLeft[i] = left[i] + w;
	}

	// junction with the nose
	{
		const int i = noseStart;
		double r = interpolate(reflectionLeft, newReflectionLeft, lambda);
		junctionOutputLeft[i] = r * right[i - 1] + (1 + r) * (noseLeft[0] + left[i]);
		r = interpolate(reflectionRight, newReflectionRight, lambda);
		junctionOutputRight[i] = r * left[i] + (1 + r) * (right[i - 1] + noseLeft[0]);
		r = interpolate(reflectionNose, newReflectionNose, lambda);
		noseJunctionOutputRight[0] = r * noseLeft[0] + (1 + r) * (left[i] + right[i - 1]);
	}

	for (int i = 0; i < n; i++) {
		const double r = junctionOutputRight[i] * 0.999;
		const double l = junctionOutputLeft[i + 1] * 0.999;
		right[i] = r;
		left[i] = l;
		const double amplitude = std::fabs(r + l);
		maxAmplitude[i] = std::fmax(maxAmplitude[i] * 0.9999, amplitude);
	}

	const double lipOutput = right[n - 1];

	// nose
	noseJunctionOutputLeft[noseLength] = noseRight[noseLength - 1] * lipReflection;

	for (int i = 1; i < noseLength; i++) {
		const double w = noseReflection[i] * (noseRight[i - 1] + noseLeft[i]);
		noseJunctionOutputRight[i] = noseRight[i - 1] - w;
		noseJunctionOutputLeft[i] = noseLeft[i] + w;
	}

	for (int i = 0; i < noseLength; i++) {
		const double r = noseJunctionOutputRight[i];
		const double l = noseJunctionOutputLeft[i + 1];
		noseRight[i] = r;
		noseLeft[i] = l;
		const double amplitude = std::fabs(r + l);
		noseMaxAmplitude[i] = std::fmax(noseMaxAmplitude[i] * 0.9999, amplitude);
	}

	const double noseOutput = noseRight[noseLength - 1];

	sampleCount++;
	time = sampleCount / tractSampleRate;

	return lipOutput + noseOutput;
}

void Tract::processTransients() {
	for (int i = (int)transients.size() - 1; i >= 0; i--) {
		const Transient &t = transients[i];
		const double timeAlive = time - t.startTime;
		if (timeAlive > t.lifeTime) {
			transients.erase(transients.begin() + i);
			continue;
		}
		const double amplitude = t.strength * std::pow(2, -t.exponent * timeAlive);
		right[t.position] += amplitude / 2;
		left[t.position] += amplitude / 2;
	}
}

void Tract::addTurbulenceNoise() {
	const double fricativeAttackTime = 0.1; // seconds
	for (const TurbulencePoint &p : turbulencePoints) {
		if (p.position < 2 || p.position > n) continue;
		if (p.diameter <= 0) continue;
		double intensity;
		if (!p.ended) {
			intensity = clamp((time - p.startTime) / fricativeAttackTime, 0, 1);
		} else { // released
			intensity = clamp(1 - (time - p.endTime) / fricativeAttackTime, 0, 1);
		}
		if (intensity <= 0) continue;
		const double turbulenceNoise = 0.66 * fricationNoise.next() * intensity * glottis.getNoiseModulator();
		addTurbulenceNoiseAtPosition(turbulenceNoise, p.position, p.diameter);
	}
}

void Tract::addTurbulenceNoiseAtPosition(double noise, double position, double diam) {
	const int i = (int)std::floor(position);
	const double delta = position - i;
	const double thinness0 = clamp(8 * (0.7 - diam), 0, 1);
	const double openness = clamp(30 * (diam - 0.3), 0, 1);
	const double noise0 = noise * (1 - delta) * thinness0 * openness;
	const double noise1 = noise * delta * thinness0 * openness;
	if (i + 1 < n) {
		right[i + 1] += noise0 / 2;
		left[i + 1] += noise0 / 2;
	}
	if (i + 2 < n) {
		right[i + 2] += noise1 / 2;
		left[i + 2] += noise1 / 2;
	}
}

} // namespace pt
