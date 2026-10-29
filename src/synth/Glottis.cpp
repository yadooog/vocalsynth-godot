#include "Glottis.h"
#include "Noise.h"
#include <cmath>

namespace pt {

Glottis::Glottis(double sampleRate_)
		: sampleRate(sampleRate_), aspirationNoise(500, 0.5, sampleRate_, 0x8000) {
	setupWaveform(0);
}

double Glottis::step(double lambda) {
	const double time = sampleCount / sampleRate;
	if (timeInWaveform > waveformLength) {
		timeInWaveform -= waveformLength;
		setupWaveform(lambda);
	}
	const double out1 = normalizedLFWaveform(timeInWaveform / waveformLength);
	const double noise = aspirationNoise.next();
	const double aspiration1 = intensity * (1 - std::sqrt(targetTenseness)) * getNoiseModulator() * noise;
	const double aspiration2 = aspiration1 * (0.2 + 0.02 * simplex1(time * 1.99));
	const double out = out1 + aspiration2;
	sampleCount++;
	timeInWaveform += 1 / sampleRate;
	return out;
}

double Glottis::getNoiseModulator() const {
	const double voiced = 0.1 + 0.2 * std::fmax(0, std::sin(PI * 2 * timeInWaveform / waveformLength));
	return targetTenseness * intensity * voiced + (1 - targetTenseness * intensity) * 0.3;
}

void Glottis::adjustParameters(double deltaTime) {
	const double d = deltaTime * sampleRate / 512; // 512 is the original block size
	const double oldTime = sampleCount / sampleRate;
	const double newTime = oldTime + deltaTime;
	adjustIntensity(d);
	calculateNewFrequency(newTime, d);
	calculateNewTenseness(newTime);
}

void Glottis::calculateNewFrequency(double time, double d) {
	if (intensity == 0) {
		smoothFrequency = targetFrequency;
	} else if (targetFrequency > smoothFrequency) {
		smoothFrequency = std::fmin(smoothFrequency * (1 + 0.1 * d), targetFrequency);
	} else if (targetFrequency < smoothFrequency) {
		smoothFrequency = std::fmax(smoothFrequency / (1 + 0.1 * d), targetFrequency);
	}
	oldFrequency = newFrequency;
	newFrequency = std::fmax(10, smoothFrequency * (1 + calculateVibrato(time)));
}

void Glottis::calculateNewTenseness(double time) {
	oldTenseness = newTenseness;
	newTenseness = std::fmax(0, targetTenseness + 0.1 * simplex1(time * 0.46) + 0.05 * simplex1(time * 0.36));
	if (!isTouched && alwaysVoice) { // attack
		newTenseness += (3 - targetTenseness) * (1 - intensity);
	}
}

void Glottis::adjustIntensity(double d) {
	if (isTouched || alwaysVoice) {
		intensity += 0.13 * d;
	} else {
		intensity -= 0.05 * d;
	}
	intensity = clamp(intensity, 0, 1);
}

double Glottis::calculateVibrato(double time) const {
	double vibrato = 0;
	vibrato += vibratoAmount * std::sin(2 * PI * time * vibratoFrequency);
	vibrato += 0.02 * simplex1(time * 4.07);
	vibrato += 0.04 * simplex1(time * 2.15);
	if (autoWobble) {
		vibrato += 0.2 * simplex1(time * 0.98);
		vibrato += 0.4 * simplex1(time * 0.5);
	}
	return vibrato;
}

void Glottis::setupWaveform(double lambda) {
	const double frequency = interpolate(oldFrequency, newFrequency, lambda);
	const double tenseness = interpolate(oldTenseness, newTenseness, lambda);
	waveformLength = 1 / frequency;
	loudness = std::pow(std::fmax(0, tenseness), 0.25);

	const double rd = clamp(3 * (1 - tenseness), 0.5, 2.7);

	// normalized to time = 1, Ee = 1
	const double ra = -0.01 + 0.048 * rd;
	const double rk = 0.224 + 0.118 * rd;
	const double rg = (rk / 4) * (0.5 + 1.2 * rk) / (0.11 * rd - ra * (0.5 + 1.2 * rk));

	const double ta = ra;
	const double tp = 1 / (2 * rg);
	const double te_ = tp + tp * rk;

	const double epsilon_ = 1 / ta;
	const double shift_ = std::exp(-epsilon_ * (1 - te_));
	const double delta_ = 1 - shift_;

	const double rhsIntegral = ((1 / epsilon_) * (shift_ - 1) + (1 - te_) * shift_) / delta_;
	const double totalLowerIntegral = rhsIntegral - (te_ - tp) / 2;
	const double totalUpperIntegral = -totalLowerIntegral;

	const double omega_ = PI / tp;
	const double s = std::sin(omega_ * te_);
	const double y = -PI * s * totalUpperIntegral / (tp * 2);
	const double z = std::log(y);
	const double alpha_ = z / (tp / 2 - te_);
	const double e0_ = -1 / (s * std::exp(alpha_ * te_));

	alpha = alpha_;
	e0 = e0_;
	epsilon = epsilon_;
	shift = shift_;
	delta = delta_;
	te = te_;
	omega = omega_;
}

double Glottis::normalizedLFWaveform(double t) const {
	double output;
	if (t > te) {
		output = (-std::exp(-epsilon * (t - te)) + shift) / delta;
	} else {
		output = e0 * std::exp(alpha * t) * std::sin(omega * t);
	}
	return output * intensity * loudness;
}

} // namespace pt
