// The vocal tract: a chain of tubes (waveguide) from throat to lips, plus the nose.
// Ported from pink-trombone-mod Tract.ts (MIT).
#pragma once
#include "Glottis.h"
#include <vector>

namespace pt {

struct Transient {
	int position;
	double startTime;
	double lifeTime; // seconds
	double strength;
	double exponent;
};

struct TurbulencePoint {
	double position;
	double diameter;
	double startTime;
	double endTime;
	bool ended; // false while the point is still held
};

class Tract {
public:
	static constexpr int n = 44;          // cells in the main tract
	static constexpr int bladeStart = 10;
	static constexpr int tipStart = 32;
	static constexpr int lipStart = 39;
	static constexpr int noseLength = 28; // cells in the nose
	static constexpr int noseStart = n - noseLength + 1;

	double time = 0;

	double diameter[n] = {};          // current tube diameters
	double maxAmplitude[n] = {};      // per-cell loudness, for drawing
	double noseDiameter[noseLength] = {}; // [0] = velum opening
	double noseMaxAmplitude[noseLength] = {};

	std::vector<Transient> transients;
	std::vector<TurbulencePoint> turbulencePoints;

	Tract(Glottis &glottis, double tractSampleRate);

	void calculateNoseReflections();
	void calculateNewBlockParameters();
	double step(double glottalOutput, double lambda);

private:
	static constexpr double glottalReflection = 0.75;
	static constexpr double lipReflection = -0.85;

	Glottis &glottis;
	double tractSampleRate;
	FilteredNoiseSource fricationNoise;
	long long sampleCount = 0;

	double right[n] = {};
	double left[n] = {};
	double reflection[n] = {};
	double newReflection[n] = {};
	double junctionOutputRight[n] = {};
	double junctionOutputLeft[n + 1] = {};

	double noseRight[noseLength] = {};
	double noseLeft[noseLength] = {};
	double noseJunctionOutputRight[noseLength] = {};
	double noseJunctionOutputLeft[noseLength + 1] = {};
	double noseReflection[noseLength] = {};

	double reflectionLeft = 0, newReflectionLeft = 0;
	double reflectionRight = 0, newReflectionRight = 0;
	double reflectionNose = 0, newReflectionNose = 0;

	void calculateMainTractReflections();
	void calculateNoseJunctionReflections();
	void processTransients();
	void addTurbulenceNoise();
	void addTurbulenceNoiseAtPosition(double noise, double position, double diameter);
};

} // namespace pt
