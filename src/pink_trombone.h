// Godot wrapper around the Pink Trombone engine in src/synth.
#pragma once

#include "synth/Synthesizer.h"

#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_generator_playback.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <memory>
#include <mutex>
#include <vector>

namespace godot {

class PinkTromboneStream;

class PinkTrombone : public RefCounted {
	GDCLASS(PinkTrombone, RefCounted)

public:
	PinkTrombone();

	void setup(double sample_rate);
	Ref<PinkTromboneStream> create_stream();
	int fill(const Ref<AudioStreamGeneratorPlayback> &playback);
	void mix(float *out, int frames); // called from the audio thread
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
	double get_level() const;
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
	// The audio thread and the game both use `synth`, so every access is locked.
	mutable std::mutex mutex;
	std::unique_ptr<pt::Synthesizer> synth;
	std::vector<float> buffer;
	double volume = 1.0;
	double level = 0.0; // smoothed loudness of what was last played (rms)
};

// An AudioStream that plays a PinkTrombone directly on Godot's audio thread,
// so changes are heard within one audio buffer (no extra queue in between).
class PinkTromboneStream : public AudioStream {
	GDCLASS(PinkTromboneStream, AudioStream)

public:
	void set_trombone(const Ref<PinkTrombone> &trombone);
	Ref<PinkTrombone> get_trombone() const;

	Ref<AudioStreamPlayback> _instantiate_playback() const override;
	String _get_stream_name() const override;
	double _get_length() const override;
	bool _is_monophonic() const override;

protected:
	static void _bind_methods();

private:
	Ref<PinkTrombone> trombone;
};

class PinkTrombonePlayback : public AudioStreamPlayback {
	GDCLASS(PinkTrombonePlayback, AudioStreamPlayback)

public:
	Ref<PinkTrombone> trombone;

	void _start(double from_pos) override;
	void _stop() override;
	bool _is_playing() const override;
	int32_t _get_loop_count() const override;
	double _get_playback_position() const override;
	void _seek(double position) override;
	int32_t _mix(AudioFrame *buffer, float rate_scale, int32_t frames) override;

protected:
	static void _bind_methods() {}

private:
	bool playing = true; // true from the start, in case _start is not called (seen on web)
	std::vector<float> mono;
};

} // namespace godot
