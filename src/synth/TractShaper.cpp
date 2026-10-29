#include "TractShaper.h"
#include <cmath>

namespace pt {

static constexpr double gridOffset = 1.7;

TractShaper::TractShaper(Tract &tract_) : tract(tract_) {
	shapeNose(true);
	tract.calculateNoseReflections(); // nose reflections are calculated once, with the velum open
	shapeNose(false);
	shapeMainTract();
}

void TractShaper::shapeMainTract() {
	for (int i = 0; i < Tract::n; i++) {
		const double d = getRestDiameter(i);
		tract.diameter[i] = d;
		targetDiameter[i] = d;
	}
}

double TractShaper::getRestDiameter(int i) const {
	if (i < 7) return 0.6;
	if (i < Tract::bladeStart) return 1.1;
	if (i >= Tract::lipStart) return 1.5;
	const double t = 1.1 * PI * (tongueIndex - i) / (Tract::tipStart - Tract::bladeStart);
	const double fixedTongueDiameter = 2 + (tongueDiameter - 2) / 1.5;
	double curve = (1.5 - fixedTongueDiameter + gridOffset) * std::cos(t);
	if (i == Tract::bladeStart - 2 || i == Tract::lipStart - 1) curve *= 0.8;
	if (i == Tract::bladeStart || i == Tract::lipStart - 2) curve *= 0.94;
	return 1.5 - curve;
}

void TractShaper::adjustTractShape(double deltaTime) {
	const double amount = deltaTime * movementSpeed;
	int newLastObstruction = -1;
	for (int i = 0; i < Tract::n; i++) {
		const double d = tract.diameter[i];
		if (d <= 0) newLastObstruction = i;
		double slowReturn;
		if (i < Tract::noseStart) {
			slowReturn = 0.6;
		} else if (i >= Tract::tipStart) {
			slowReturn = 1;
		} else {
			slowReturn = 0.6 + 0.4 * (i - Tract::noseStart) / (Tract::tipStart - Tract::noseStart);
		}
		tract.diameter[i] = moveTowards(d, targetDiameter[i], slowReturn * amount, 2 * amount);
	}
	if (lastObstruction > -1 && newLastObstruction == -1 && tract.noseDiameter[0] < 0.223) {
		addTransient(lastObstruction);
	}
	lastObstruction = newLastObstruction;
	tract.noseDiameter[0] = moveTowards(tract.noseDiameter[0], velumTarget, amount * 0.25, amount * 0.1);
}

void TractShaper::addTransient(int position) {
	tract.transients.push_back(Transient{ position, tract.time, 0.2, 0.3, 200 });
}

void TractShaper::shapeNose(bool velumOpen) {
	velumTarget = velumOpen ? velumOpenTarget : velumClosedTarget;
	for (int i = 0; i < Tract::noseLength; i++) {
		double d;
		const double x = 2.0 * i / Tract::noseLength;
		if (i == 0) {
			d = velumTarget;
		} else if (x < 1) {
			d = 0.4 + 1.6 * x;
		} else {
			d = 0.5 + 1.5 * (2 - x);
		}
		tract.noseDiameter[i] = std::fmin(d, 1.9);
	}
}

} // namespace pt
