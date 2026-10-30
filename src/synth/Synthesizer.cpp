#include "Synthesizer.h"
#include <algorithm>
#include <cmath>

namespace pt {

static constexpr int maxBlockLength = 512;

Synthesizer::Synthesizer(double sampleRate_)
		: glottis(sampleRate_), tract(glottis, 2 * sampleRate_), // tract runs at twice the sample rate
		  shaper(tract), sampleRate(sampleRate_) {
	calculateNewBlockParameters(0);
}

void Synthesizer::synthesize(float *out, int count) {
	int p = 0;
	while (p < count) {
		const int len = std::min(maxBlockLength, count - p);
		synthesizeBlock(out + p, len);
		p += len;
	}
}

void Synthesizer::synthesizeBlock(float *out, int count) {
	const double deltaTime = count / sampleRate;
	applyTouches();
	calculateNewBlockParameters(deltaTime);
	const double size = clamp(voiceSize, 0.25, 4.0);
	tract.setStepRate(2 * sampleRate / size);
	if (size != 1.0) {
		// The tract takes 2/size steps per output sample. Glottis samples are averaged
		// into each step, and the steps are averaged (or interpolated) back to the output.
		const double stepsPerSample = 2 / size;
		const double gain = 0.25 / std::sqrt(size); // keeps loudness roughly even across sizes
		for (int i = 0; i < count; i++) {
			const double lambda = (i + 0.5) / count;
			glottalSum += glottis.step((double)i / count);
			glottalCount++;
			stepPhase += stepsPerSample;
			double sum = 0;
			int steps = 0;
			while (stepPhase >= 1) {
				stepPhase -= 1;
				if (glottalCount > 0) {
					lastGlottalInput = glottalSum / glottalCount;
					glottalSum = 0;
					glottalCount = 0;
				}
				const double input = lastGlottalInput;
				prevTractOut = lastTractOut;
				lastTractOut = tract.step(input, lambda);
				sum += lastTractOut;
				steps++;
			}
			const double v = steps > 0 ? sum / steps : interpolate(prevTractOut, lastTractOut, stepPhase);
			out[i] = (float)(v * gain);
		}
		return;
	}
	for (int i = 0; i < count; i++) {
		const double lambda1 = (double)i / count;
		const double lambda2 = (i + 0.5) / count;
		const double glottalOutput = glottis.step(lambda1);
		const double v1 = tract.step(glottalOutput, lambda1);
		const double v2 = tract.step(glottalOutput, lambda2);
		out[i] = (float)((v1 + v2) * 0.125);
	}
}

void Synthesizer::calculateNewBlockParameters(double deltaTime) {
	glottis.adjustParameters(deltaTime);
	shaper.adjustTractShape(deltaTime);
	tract.calculateNewBlockParameters();
}

Synthesizer::Touch *Synthesizer::findAlive(int id) {
	for (Touch &t : touches) {
		if (t.id == id && t.alive) return &t;
	}
	return nullptr;
}

void Synthesizer::touchStart(int id, double index, double diameter) {
	touchEnd(id);
	touches.push_back(Touch{ id, index, diameter, tract.time, 0, true });
}

void Synthesizer::touchMove(int id, double index, double diameter) {
	if (Touch *t = findAlive(id)) {
		t->index = index;
		t->diameter = diameter;
	}
}

void Synthesizer::touchEnd(int id) {
	if (Touch *t = findAlive(id)) {
		t->alive = false;
		t->endTime = tract.time;
	}
}

void Synthesizer::clearTouches() {
	for (Touch &t : touches) {
		if (t.alive) { t.alive = false; t.endTime = tract.time; }
	}
}

void Synthesizer::setTongue(double index, double diameter) {
	double fromPoint = (outerTongueControlRadius - diameter) / (outerTongueControlRadius - innerTongueControlRadius);
	fromPoint = clamp(fromPoint, 0, 1);
	fromPoint = std::pow(fromPoint, 0.58) - 0.2 * (fromPoint * fromPoint - fromPoint); // fits the curve to a straight line
	shaper.tongueDiameter = clamp(diameter, innerTongueControlRadius, outerTongueControlRadius);
	const double out = tongueFullRange ? 0.5 * (tongueUpperIndexBound - tongueLowerIndexBound) : fromPoint * 0.5 * (tongueUpperIndexBound - tongueLowerIndexBound);
	shaper.tongueIndex = clamp(index, tongueIndexCentre - out, tongueIndexCentre + out);
}

// Same as TractUi.handleTouches in the original.
void Synthesizer::applyTouches() {
	const double time = tract.time;
	// forget touches released more than a second ago
	touches.erase(std::remove_if(touches.begin(), touches.end(),
			[time](const Touch &t) { return !t.alive && time > t.endTime + 1; }),
			touches.end());

	tract.turbulencePoints.clear();
	for (const Touch &t : touches) {
		tract.turbulencePoints.push_back(TurbulencePoint{ t.index, t.diameter, t.startTime, t.endTime, !t.alive });
	}
	for (int i = 0; i < Tract::n; i++) {
		shaper.targetDiameter[i] = shaper.getRestDiameter(i);
	}
	applyJawAndLips();
	bool velumOpen = velumForcedOpen;
	for (const Touch &t : touches) {
		if (!t.alive) continue;
		if (t.index > Tract::noseStart && t.diameter < -noseOffset) velumOpen = true;
		if (t.diameter < -0.85 - noseOffset) continue;
		reduceTargetDiametersByTouch(t.index, std::fmax(0, t.diameter - 0.3));
	}
	shaper.velumTarget = velumOpen ? TractShaper::velumOpenTarget : TractShaper::velumClosedTarget;
}

// Jaw scales the whole mouth (fading in from the throat); lips set the last few cells.
void Synthesizer::applyJawAndLips() {
	if (jaw != 0.5) {
		const double factor = 0.5 + clamp(jaw, 0, 1);
		const int fadeStart = 7, fadeEnd = Tract::bladeStart + 2;
		for (int i = fadeStart; i < Tract::n; i++) {
			const double amount = clamp((double)(i - fadeStart) / (fadeEnd - fadeStart), 0, 1);
			shaper.targetDiameter[i] *= 1 + (factor - 1) * amount;
		}
	}
	if (lips != 1.0) {
		const double l = clamp(lips, 0, 2);
		for (int i = Tract::lipStart - 1; i < Tract::n; i++) {
			const double amount = (i == Tract::lipStart - 1) ? 0.5 : 1.0; // soften the corner
			shaper.targetDiameter[i] *= 1 + (l - 1) * amount;
		}
	}
}

void Synthesizer::reduceTargetDiametersByTouch(double index, double diameter) {
	if (index < 2 || index >= Tract::n || diameter >= 3) return;
	double width;
	if (index < 25) {
		width = 10;
	} else if (index >= Tract::tipStart) {
		width = 5;
	} else {
		width = 10 - 5 * (index - 25) / (Tract::tipStart - 25);
	}
	for (int i = -(int)std::ceil(width) - 1; i < width + 1; i++) {
		const int p = (int)std::floor(index + 0.5) + i; // JS Math.round
		if (p < 0 || p >= Tract::n) continue;
		const double relpos = std::fabs(p - index) - 0.5;
		double shrink;
		if (relpos <= 0) {
			shrink = 0;
		} else if (relpos > width) {
			shrink = 1;
		} else {
			shrink = 0.5 * (1 - std::cos(PI * relpos / width));
		}
		if (diameter < shaper.targetDiameter[p]) {
			shaper.targetDiameter[p] = diameter + (shaper.targetDiameter[p] - diameter) * shrink;
		}
	}
}

} // namespace pt
