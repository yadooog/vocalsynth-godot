// Ties glottis, tract and shaper together and turns "touches" into tract shapes.
// Touch handling is ported from pink-trombone-mod TractUi.ts (MIT), minus the drawing.
//
// Positions along the tract use two numbers, the same as the original:
//   index    - 0 at the throat, ~39 at the lips, 44 past the lips
//   diameter - distance in from the outer (roof) wall; 0 = touching the roof,
//              negative = above the roof (closes the tract / opens the nose).
#pragma once
#include "TractShaper.h"
#include <vector>

namespace pt {

class Synthesizer {
public:
	// Tongue control area, in tract units (as drawn in the original).
	static constexpr double tongueLowerIndexBound = Tract::bladeStart + 2;
	static constexpr double tongueUpperIndexBound = Tract::tipStart - 3;
	static constexpr double tongueIndexCentre = 0.5 * (tongueLowerIndexBound + tongueUpperIndexBound);
	static constexpr double innerTongueControlRadius = 2.05;
	static constexpr double outerTongueControlRadius = 3.5;
	static constexpr double noseOffset = 0.8;

	Glottis glottis;
	Tract tract;
	TractShaper shaper;
	bool velumForcedOpen = false; // open the nose without a touch ("hum")

	// Voice size: 1 = the original. 2 = tract twice as long (giant), 0.5 = half (tiny).
	double voiceSize = 1.0;
	// Jaw: 0 = nearly closed, 0.5 = the original, 1 = wide open.
	double jaw = 0.5;
	// Lips: 0 = closed, 1 = the original, up to ~1.4 = spread wide.
	double lips = 1.0;

	explicit Synthesizer(double sampleRate);

	// Fills `out` with `count` mono samples.
	void synthesize(float *out, int count);

	// Touches on the tract (fingers / mouse). `id` is any number you pick per finger.
	void touchStart(int id, double index, double diameter);
	void touchMove(int id, double index, double diameter);
	void touchEnd(int id);
	void clearTouches();

	// Move the tongue as if dragging the tongue control to (index, diameter).
	void setTongue(double index, double diameter);

	double getTime() const { return tract.time; }

private:
	struct Touch {
		int id;
		double index, diameter;
		double startTime, endTime;
		bool alive;
	};
	double sampleRate;
	std::vector<Touch> touches;

	// state for resampling the tract when voiceSize != 1
	double stepPhase = 0;
	double glottalSum = 0;
	int glottalCount = 0;
	double lastGlottalInput = 0;
	double prevTractOut = 0, lastTractOut = 0;

	void applyJawAndLips();

	Touch *findAlive(int id);
	void applyTouches();
	void reduceTargetDiametersByTouch(double index, double diameter);
	void synthesizeBlock(float *out, int count);
	void calculateNewBlockParameters(double deltaTime);
};

} // namespace pt
