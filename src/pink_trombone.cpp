#include "pink_trombone.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

#define LOCK std::lock_guard<std::mutex> lock(mutex)

PinkTrombone::PinkTrombone() {
	setup(44100);
}

void PinkTrombone::setup(double sample_rate) {
	LOCK;
	synth = std::make_unique<pt::Synthesizer>(sample_rate);
}

Ref<PinkTromboneStream> PinkTrombone::create_stream() {
	Ref<PinkTromboneStream> stream;
	stream.instantiate();
	stream->set_trombone(Ref<PinkTrombone>(this));
	return stream;
}

void PinkTrombone::mix(float *out, int frames) {
	LOCK;
	synth->synthesize(out, frames);
	const float v = (float)volume;
	double sum = 0;
	for (int i = 0; i < frames; i++) {
		out[i] *= v;
		sum += (double)out[i] * out[i];
	}
	// Smooth over roughly a tenth of a second, whatever the buffer size.
	const double rms = frames > 0 ? std::sqrt(sum / frames) : 0.0;
	const double k = 1.0 - std::exp(-frames / (0.1 * 44100.0));
	level += (rms - level) * k;
}

double PinkTrombone::get_level() const { LOCK; return level; }

// Pushes as many frames as the generator has room for. Call every frame from _process.
int PinkTrombone::fill(const Ref<AudioStreamGeneratorPlayback> &playback) {
	if (playback.is_null()) return 0;
	const int frames = playback->get_frames_available();
	if (frames <= 0) return 0;
	buffer.resize(frames);
	mix(buffer.data(), frames);
	PackedVector2Array out;
	out.resize(frames);
	Vector2 *w = out.ptrw();
	for (int i = 0; i < frames; i++) {
		w[i] = Vector2(buffer[i], buffer[i]);
	}
	playback->push_buffer(out);
	return frames;
}

// Renders mono samples without a player, e.g. to save a sound.
PackedFloat32Array PinkTrombone::generate(int frames) {
	PackedFloat32Array out;
	if (frames <= 0) return out;
	out.resize(frames);
	LOCK;
	synth->synthesize(out.ptrw(), frames);
	return out;
}

void PinkTrombone::touch_start(int id, double index, double diameter) { LOCK; synth->touchStart(id, index, diameter); }
void PinkTrombone::touch_move(int id, double index, double diameter) { LOCK; synth->touchMove(id, index, diameter); }
void PinkTrombone::touch_end(int id) { LOCK; synth->touchEnd(id); }
void PinkTrombone::clear_touches() { LOCK; synth->clearTouches(); }
void PinkTrombone::set_tongue(double index, double diameter) { LOCK; synth->setTongue(index, diameter); }
double PinkTrombone::get_tongue_index() const { LOCK; return synth->shaper.tongueIndex; }
double PinkTrombone::get_tongue_diameter() const { LOCK; return synth->shaper.tongueDiameter; }

void PinkTrombone::set_frequency(double v) { LOCK; synth->glottis.targetFrequency = v; }
double PinkTrombone::get_frequency() const { LOCK; return synth->glottis.targetFrequency; }
void PinkTrombone::set_tenseness(double v) { LOCK; synth->glottis.targetTenseness = pt::clamp(v, 0, 1); }
double PinkTrombone::get_tenseness() const { LOCK; return synth->glottis.targetTenseness; }
void PinkTrombone::set_voice_held(bool v) { LOCK; synth->glottis.isTouched = v; }
bool PinkTrombone::get_voice_held() const { LOCK; return synth->glottis.isTouched; }
void PinkTrombone::set_always_voice(bool v) { LOCK; synth->glottis.alwaysVoice = v; }
bool PinkTrombone::get_always_voice() const { LOCK; return synth->glottis.alwaysVoice; }
void PinkTrombone::set_auto_wobble(bool v) { LOCK; synth->glottis.autoWobble = v; }
bool PinkTrombone::get_auto_wobble() const { LOCK; return synth->glottis.autoWobble; }
void PinkTrombone::set_vibrato_amount(double v) { LOCK; synth->glottis.vibratoAmount = v; }
double PinkTrombone::get_vibrato_amount() const { LOCK; return synth->glottis.vibratoAmount; }
void PinkTrombone::set_velum_open(bool v) { LOCK; synth->velumForcedOpen = v; }
bool PinkTrombone::get_velum_open() const { LOCK; return synth->velumForcedOpen; }
void PinkTrombone::set_voice_size(double v) { LOCK; synth->voiceSize = pt::clamp(v, 0.25, 4.0); }
double PinkTrombone::get_voice_size() const { LOCK; return synth->voiceSize; }
void PinkTrombone::set_jaw(double v) { LOCK; synth->jaw = pt::clamp(v, 0, 1); }
double PinkTrombone::get_jaw() const { LOCK; return synth->jaw; }
void PinkTrombone::set_lips(double v) { LOCK; synth->lips = pt::clamp(v, 0, 2); }
void PinkTrombone::set_tongue_full_range(bool v) { LOCK; synth->tongueFullRange = v; }
bool PinkTrombone::get_tongue_full_range() const { LOCK; return synth->tongueFullRange; }
double PinkTrombone::get_lips() const { LOCK; return synth->lips; }
void PinkTrombone::set_volume(double v) { LOCK; volume = v; }
double PinkTrombone::get_volume() const { LOCK; return volume; }

static PackedFloat32Array to_array(const double *values, int count) {
	PackedFloat32Array a;
	a.resize(count);
	float *w = a.ptrw();
	for (int i = 0; i < count; i++) w[i] = (float)values[i];
	return a;
}

PackedFloat32Array PinkTrombone::get_diameters() const { LOCK; return to_array(synth->tract.diameter, pt::Tract::n); }
PackedFloat32Array PinkTrombone::get_nose_diameters() const { LOCK; return to_array(synth->tract.noseDiameter, pt::Tract::noseLength); }
PackedFloat32Array PinkTrombone::get_amplitudes() const { LOCK; return to_array(synth->tract.maxAmplitude, pt::Tract::n); }
PackedFloat32Array PinkTrombone::get_nose_amplitudes() const { LOCK; return to_array(synth->tract.noseMaxAmplitude, pt::Tract::noseLength); }
double PinkTrombone::get_time() const { LOCK; return synth->getTime(); }

#define PROP(type, name) \
	ClassDB::bind_method(D_METHOD("set_" #name, "value"), &PinkTrombone::set_##name); \
	ClassDB::bind_method(D_METHOD("get_" #name), &PinkTrombone::get_##name); \
	ADD_PROPERTY(PropertyInfo(Variant::type, #name), "set_" #name, "get_" #name);

void PinkTrombone::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "sample_rate"), &PinkTrombone::setup);
	ClassDB::bind_method(D_METHOD("create_stream"), &PinkTrombone::create_stream);
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
	PROP(BOOL, tongue_full_range)
	PROP(FLOAT, voice_size)
	PROP(FLOAT, jaw)
	PROP(FLOAT, lips)
	PROP(FLOAT, volume)

	ClassDB::bind_method(D_METHOD("get_diameters"), &PinkTrombone::get_diameters);
	ClassDB::bind_method(D_METHOD("get_nose_diameters"), &PinkTrombone::get_nose_diameters);
	ClassDB::bind_method(D_METHOD("get_amplitudes"), &PinkTrombone::get_amplitudes);
	ClassDB::bind_method(D_METHOD("get_nose_amplitudes"), &PinkTrombone::get_nose_amplitudes);
	ClassDB::bind_method(D_METHOD("get_time"), &PinkTrombone::get_time);
	ClassDB::bind_method(D_METHOD("get_level"), &PinkTrombone::get_level);

	// Tract layout, so scripts don't have to hard-code it.
	ClassDB::bind_integer_constant(get_class_static(), "", "TRACT_LENGTH", pt::Tract::n);
	ClassDB::bind_integer_constant(get_class_static(), "", "NOSE_LENGTH", pt::Tract::noseLength);
	ClassDB::bind_integer_constant(get_class_static(), "", "NOSE_START", pt::Tract::noseStart);
	ClassDB::bind_integer_constant(get_class_static(), "", "BLADE_START", pt::Tract::bladeStart);
	ClassDB::bind_integer_constant(get_class_static(), "", "TIP_START", pt::Tract::tipStart);
	ClassDB::bind_integer_constant(get_class_static(), "", "LIP_START", pt::Tract::lipStart);
}

// ---------------------------------------------------------------- stream

void PinkTromboneStream::set_trombone(const Ref<PinkTrombone> &t) { trombone = t; }
Ref<PinkTrombone> PinkTromboneStream::get_trombone() const { return trombone; }

Ref<AudioStreamPlayback> PinkTromboneStream::_instantiate_playback() const {
	Ref<PinkTrombonePlayback> playback;
	playback.instantiate();
	playback->trombone = trombone;
	return playback;
}

String PinkTromboneStream::_get_stream_name() const { return "PinkTrombone"; }
double PinkTromboneStream::_get_length() const { return 0; }
bool PinkTromboneStream::_is_monophonic() const { return true; }

void PinkTromboneStream::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_trombone", "trombone"), &PinkTromboneStream::set_trombone);
	ClassDB::bind_method(D_METHOD("get_trombone"), &PinkTromboneStream::get_trombone);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "trombone", PROPERTY_HINT_RESOURCE_TYPE, "PinkTrombone", PROPERTY_USAGE_NONE), "set_trombone", "get_trombone");
}

void PinkTrombonePlayback::_start(double) { playing = true; }
void PinkTrombonePlayback::_stop() { playing = false; }
bool PinkTrombonePlayback::_is_playing() const { return playing; }
int32_t PinkTrombonePlayback::_get_loop_count() const { return 0; }
double PinkTrombonePlayback::_get_playback_position() const { return 0; }
void PinkTrombonePlayback::_seek(double) {}

int32_t PinkTrombonePlayback::_mix(AudioFrame *buffer, float, int32_t frames) {
	if (!playing || trombone.is_null()) {
		for (int i = 0; i < frames; i++) buffer[i] = AudioFrame{ 0, 0 };
		return frames;
	}
	if ((int)mono.size() < frames) mono.resize(frames);
	trombone->mix(mono.data(), frames);
	for (int i = 0; i < frames; i++) {
		buffer[i].left = mono[i];
		buffer[i].right = mono[i];
	}
	return frames;
}
