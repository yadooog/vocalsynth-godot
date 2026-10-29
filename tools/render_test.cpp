// Renders tools/scenario.json with the C++ engine to a raw float32 file (and a .wav).
// Used to check the port against the original JavaScript (see tools/README.md).
// Build: g++ -O2 -std=c++17 -I../src tools/render_test.cpp ../src/synth/*.cpp
#include "synth/Synthesizer.h"
#include "synth/Noise.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

// Same tiny LCG as compare_js.mjs so both sides use identical "random" numbers.
static uint32_t lcgState = 1;
static double lcg() {
	lcgState = (uint32_t)((uint64_t)lcgState * 1664525u + 1013904223u);
	return lcgState / 4294967296.0;
}

struct Event { int block; std::string type; int id; double index, diameter, frequency, tenseness; bool touched; };

// Minimal parser for the flat scenario file.
static double num(const std::string &obj, const char *key, double def = 0) {
	auto p = obj.find(std::string("\"") + key + "\"");
	if (p == std::string::npos) return def;
	p = obj.find(':', p);
	return std::stod(obj.substr(p + 1));
}
static std::string str(const std::string &obj, const char *key) {
	auto p = obj.find(std::string("\"") + key + "\"");
	p = obj.find('"', obj.find(':', p));
	return obj.substr(p + 1, obj.find('"', p + 1) - p - 1);
}

int main(int argc, char **argv) {
	const char *scenarioPath = argc > 1 ? argv[1] : "tools/scenario.json";
	const char *outPath = argc > 2 ? argv[2] : "cpp_out";
	std::ifstream f(scenarioPath);
	std::stringstream ss; ss << f.rdbuf();
	const std::string s = ss.str();
	const double sampleRate = num(s, "sampleRate");
	const int blocks = (int)num(s, "blocks");
	std::vector<Event> events;
	for (size_t p = s.find('{', s.find("events")); p != std::string::npos; p = s.find('{', p + 1)) {
		const std::string o = s.substr(p, s.find('}', p) - p + 1);
		events.push_back({ (int)num(o, "block"), str(o, "type"), (int)num(o, "id"), num(o, "index"), num(o, "diameter"),
				num(o, "frequency"), num(o, "tenseness"), o.find("\"touched\": true") != std::string::npos });
	}

	pt::setRandomSource(lcg);
	pt::setNoiseSeed(num(s, "seed"));
	pt::Synthesizer synth(sampleRate);

	std::vector<float> out(blocks * 512);
	for (int b = 0; b < blocks; b++) {
		for (const Event &e : events) {
			if (e.block != b) continue;
			if (e.type == "tongue") { synth.setTongue(e.index, e.diameter); synth.touchStart(e.id, e.index, e.diameter); }
			else if (e.type == "tongueMove") { synth.setTongue(e.index, e.diameter); synth.touchMove(e.id, e.index, e.diameter); }
			else if (e.type == "touch") synth.touchStart(e.id, e.index, e.diameter);
			else if (e.type == "end") synth.touchEnd(e.id);
			else if (e.type == "pitch") {
				synth.glottis.targetFrequency = e.frequency;
				synth.glottis.targetTenseness = e.tenseness;
				synth.glottis.isTouched = e.touched;
			}
		}
		synth.synthesize(out.data() + b * 512, 512);
	}

	std::ofstream raw(std::string(outPath) + ".f32", std::ios::binary);
	raw.write((const char *)out.data(), out.size() * sizeof(float));

	// 16-bit wav for listening
	std::ofstream wav(std::string(outPath) + ".wav", std::ios::binary);
	auto u32 = [&](uint32_t v) { wav.write((const char *)&v, 4); };
	auto u16 = [&](uint16_t v) { wav.write((const char *)&v, 2); };
	const uint32_t dataBytes = (uint32_t)out.size() * 2;
	wav.write("RIFF", 4); u32(36 + dataBytes); wav.write("WAVEfmt ", 8);
	u32(16); u16(1); u16(1); u32((uint32_t)sampleRate); u32((uint32_t)sampleRate * 2); u16(2); u16(16);
	wav.write("data", 4); u32(dataBytes);
	for (float v : out) {
		float c = v < -1 ? -1 : (v > 1 ? 1 : v);
		u16((uint16_t)(int16_t)(c * 32767));
	}
	std::printf("wrote %zu samples to %s.f32 / .wav\n", out.size(), outPath);
	return 0;
}
