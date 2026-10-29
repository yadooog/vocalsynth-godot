// Moves the tract walls towards a target shape (tongue position, constrictions, velum).
// Ported from pink-trombone-mod TractShaper.ts (MIT).
#pragma once
#include "Tract.h"

namespace pt {

class TractShaper {
public:
	static constexpr double velumOpenTarget = 0.4;
	static constexpr double velumClosedTarget = 0.01;

	double targetDiameter[Tract::n] = {};
	double velumTarget = velumClosedTarget;
	double tongueIndex = 12.9;
	double tongueDiameter = 2.43;

	explicit TractShaper(Tract &tract);

	double getRestDiameter(int i) const;
	void adjustTractShape(double deltaTime);

private:
	static constexpr double movementSpeed = 15; // cm per second
	Tract &tract;
	int lastObstruction = -1;

	void shapeMainTract();
	void shapeNose(bool velumOpen);
	void addTransient(int position);
};

} // namespace pt
