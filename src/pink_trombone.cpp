#include "pink_trombone.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

PinkTrombone::PinkTrombone() {
	setup(44100);
}

void PinkTrombone::setup(double sample_rate) {
	synth = std::make_unique<pt::Synthesizer>(sample_rate);
}

// Pushes as many frames as the generator has room for. Call every frame from _process.
int PinkTrombone::fill(const Ref<AudioStreamGeneratorPlayback> &playback) {
	if (playback.is_null()) return 0;
	const int frames = playback->get_frames_available();
	if (frames <= 0) return 0;
	buffer.resize(frames);
	synth->synthesize(buffer.data(), frames);
	PackedVector2Array out;
	out.resize(frames);
	Vector2 *w = out.ptrw();
	for (int i = 0; i < frames; i++) {
		const float v = buffer[i] * (float)volume;
		w[i] = Vector2(v, v);
	}
	playback->push_buffer(out);
	return frames;
}

// Renders mono samples without a player, e.g. to save a sound.
PackedFloat32Array PinkTrombone::generate(int frames) {
	PackedFloat32Array out;
	if (frames <= 0) return out;
	out.resize(frames);
	synth->synthesize(out.ptrw(), frames);
	return out;
}

void PinkTrombone::touch_start(int id, double index, double diameter) { synth->touchStart(id, index, diameter); }
void PinkTrombone::touch_move(int id, double index, double diameter) { synth->touchMove(id, index, diameter); }
void PinkTrombone::touch_end(int id) { synth->touchEnd(id); }
void PinkTrombone::clear_touches() { synth->clearTouches(); }
void PinkTrombone::set_tongue(double index, double diameter) { synth->setTongue(index, diameter); }
double PinkTrombone::get_tongue_index() const { return synth->shaper.tongueIndex; }
double PinkTrombone::get_tongue_diameter() const { return synth->shaper.tongueDiameter; }

void PinkTrombone::set_frequency(double v) { synth->glottis.targetFrequency = v; }
double PinkTrombone::get_frequency() const { return synth->glottis.targetFrequency; }
void PinkTrombone::set_tenseness(double v) { synth->glottis.targetTenseness = pt::clamp(v, 0, 1); }
double PinkTrombone::get_tenseness() const { return synth->glottis.targetTenseness; }
void PinkTrombone::set_voice_held(bool v) { synth->glottis.isTouched = v; }
bool PinkTrombone::get_voice_held() const { return synth->glottis.isTouched; }
void PinkTrombone::set_always_voice(bool v) { synth->glottis.alwaysVoice = v; }
bool PinkTrombone::get_always_voice() const { return synth->glottis.alwaysVoice; }
void PinkTrombone::set_auto_wobble(bool v) { synth->glottis.autoWobble = v; }
bool PinkTrombone::get_auto_wobble() const { return synth->glottis.autoWobble; }
void PinkTrombone::set_vibrato_amount(double v) { synth->glottis.vibratoAmount = v; }
double PinkTrombone::get_vibrato_amount() const { return synth->glottis.vibratoAmount; }
void PinkTrombone::set_velum_open(bool v) { synth->velumForcedOpen = v; }
bool PinkTrombone::get_velum_open() const { return synth->velumForcedOpen; }
void PinkTrombone::set_volume(double v) { volume = v; }
double PinkTrombone::get_volume() const { return volume; }

static PackedFloat32Array to_array(const double *values, int count) {
	PackedFloat32Array a;
	a.resize(count);
	float *w = a.ptrw();
	for (int i = 0; i < count; i++) w[i] = (float)values[i];
	return a;
}

PackedFloat32Array PinkTrombone::get_diameters() const { return to_array(synth->tract.diameter, pt::Tract::n); }
PackedFloat32Array PinkTrombone::get_nose_diameters() const { return to_array(synth->tract.noseDiameter, pt::Tract::noseLength); }
PackedFloat32Array PinkTrombone::get_amplitudes() const { return to_array(synth->tract.maxAmplitude, pt::Tract::n); }
PackedFloat32Array PinkTrombone::get_nose_amplitudes() const { return to_array(synth->tract.noseMaxAmplitude, pt::Tract::noseLength); }
double PinkTrombone::get_time() const { return synth->getTime(); }

#define PROP(type, name) \
	ClassDB::bind_method(D_METHOD("set_" #name, "value"), &PinkTrombone::set_##name); \
	ClassDB::bind_method(D_METHOD("get_" #name), &PinkTrombone::get_##name); \
	ADD_PROPERTY(PropertyInfo(Variant::type, #name), "set_" #name, "get_" #name);

void PinkTrombone::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "sample_rate"), &PinkTrombone::setup);
	ClassDB::bind_method(D_METHOD("fill", "playback"), &PinkTrombone::fill);
	ClassDB::bind_method(D_METHOD("generate", "frames"), &PinkTrombone::generate);

	ClassDB::bind_method(D_METHOD("touch_start", "id", "index", "diameter"), &PinkTrombone::touch_start);
	ClassDB::bind_method(D_METHOD("touch_move", "id", "index", "diameter"), &PinkTrombone::touch_move);
	ClassDB::bind_method(D_METHOD("touch_end", "id"), &PinkTrombone::touch_end);
	ClassDB::bind_method(D_METHOD("clear_touches"), &PinkTrombone::clear_touches);
	ClassDB::bind_method(D_METHOD("set_tongue", "index", "diameter"), &PinkTrombone::set_tongue);
	ClassDB::bind_method(D_METHOD("get_tongue_index"), &PinkTrombone::get_tongue_index);
	ClassDB::bind_method(D_METHOD("get_tongue_diameter"), &PinkTrombone::get_tongue_diameter);

	PROP(FLOAT, frequency)
	PROP(FLOAT, tenseness)
	PROP(BOOL, voice_held)
	PROP(BOOL, always_voice)
	PROP(BOOL, auto_wobble)
	PROP(FLOAT, vibrato_amount)
	PROP(BOOL, velum_open)
	PROP(FLOAT, volume)

	ClassDB::bind_method(D_METHOD("get_diameters"), &PinkTrombone::get_diameters);
	ClassDB::bind_method(D_METHOD("get_nose_diameters"), &PinkTrombone::get_nose_diameters);
	ClassDB::bind_method(D_METHOD("get_amplitudes"), &PinkTrombone::get_amplitudes);
	ClassDB::bind_method(D_METHOD("get_nose_amplitudes"), &PinkTrombone::get_nose_amplitudes);
	ClassDB::bind_method(D_METHOD("get_time"), &PinkTrombone::get_time);

	// Tract layout, so scripts don't have to hard-code it.
	ClassDB::bind_integer_constant(get_class_static(), "", "TRACT_LENGTH", pt::Tract::n);
	ClassDB::bind_integer_constant(get_class_static(), "", "NOSE_LENGTH", pt::Tract::noseLength);
	ClassDB::bind_integer_constant(get_class_static(), "", "NOSE_START", pt::Tract::noseStart);
	ClassDB::bind_integer_constant(get_class_static(), "", "BLADE_START", pt::Tract::bladeStart);
	ClassDB::bind_integer_constant(get_class_static(), "", "TIP_START", pt::Tract::tipStart);
	ClassDB::bind_integer_constant(get_class_static(), "", "LIP_START", pt::Tract::lipStart);
}
