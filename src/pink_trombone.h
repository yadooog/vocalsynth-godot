// Godot wrapper around the Pink Trombone engine in src/synth.
#pragma once

#include "synth/Synthesizer.h"

#include <godot_cpp/classes/audio_stream_generator_playback.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <memory>
#include <vector>

namespace godot {

class PinkTrombone : public RefCounted {
	GDCLASS(PinkTrombone, RefCounted)

public:
	PinkTrombone();

	void setup(double sample_rate);
	int fill(const Ref<AudioStreamGeneratorPlayback> &playback);
	PackedFloat32Array generate(int frames);

	void touch_start(int id, double index, double diameter);
	void touch_move(int id, double index, double diameter);
	void touch_end(int id);
	void clear_touches();
	void set_tongue(double index, double diameter);
	double get_tongue_index() const;
	double get_tongue_diameter() const;

	void set_frequency(double v);
	double get_frequency() const;
	void set_tenseness(double v);
	double get_tenseness() const;
	void set_voice_held(bool v);
	bool get_voice_held() const;
	void set_always_voice(bool v);
	bool get_always_voice() const;
	void set_auto_wobble(bool v);
	bool get_auto_wobble() const;
	void set_vibrato_amount(double v);
	double get_vibrato_amount() const;
	void set_velum_open(bool v);
	bool get_velum_open() const;
	void set_voice_size(double v);
	double get_voice_size() const;
	void set_jaw(double v);
	double get_jaw() const;
	void set_lips(double v);
	double get_lips() const;
	void set_volume(double v);
	double get_volume() const;

	PackedFloat32Array get_diameters() const;
	PackedFloat32Array get_nose_diameters() const;
	PackedFloat32Array get_amplitudes() const;
	PackedFloat32Array get_nose_amplitudes() const;
	double get_time() const;

protected:
	static void _bind_methods();

private:
	std::unique_ptr<pt::Synthesizer> synth;
	std::vector<float> buffer;
	double volume = 1.0;
};

} // namespace godot
