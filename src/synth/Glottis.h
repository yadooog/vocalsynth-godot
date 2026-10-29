// The voice source: vocal folds, modelled with the LF waveform plus breath noise.
// Ported from pink-trombone-mod Glottis.ts (MIT).
#pragma once
#include "Utils.h"

namespace pt {

class Glottis {
public:
	bool alwaysVoice = true;       // keep voicing even when nobody is holding the pitch control
	bool autoWobble = true;        // slow random pitch drift
	bool isTouched = false;        // pitch control is being held
	double targetTenseness = 0.6;  // 0 = breathy, 1 = tense
	double targetFrequency = 140;  // Hz
	double vibratoAmount = 0.005;
	double vibratoFrequency = 6;

	explicit Glottis(double sampleRate);

	double step(double lambda);
	double getNoiseModulator() const;
	void adjustParameters(double deltaTime);

private:
	double sampleRate;
	long long sampleCount = 0;
	double intensity = 0;
	double loudness = 1;
	double smoothFrequency = 140;
	double timeInWaveform = 0;
	double newTenseness = 0.6;
	double oldTenseness = 0.6;
	double newFrequency = 140;
	double oldFrequency = 140;
	FilteredNoiseSource aspirationNoise;

	double waveformLength = 0;
	double alpha = 0, e0 = 0, epsilon = 0, shift = 0, delta = 0, te = 0, omega = 0;

	void calculateNewFrequency(double time, double delta);
	void calculateNewTenseness(double time);
	void adjustIntensity(double delta);
	double calculateVibrato(double time) const;
	void setupWaveform(double lambda);
	double normalizedLFWaveform(double t) const;
};

} // namespace pt
