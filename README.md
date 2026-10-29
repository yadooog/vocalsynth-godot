# Vocal Synth (Godot)

The Pink Trombone voice synthesiser, running inside Godot 4. Drag the tongue,
pinch the tract, open the nose and slide the pitch, and hear it live.

The sound engine is a C++ port of [pink-trombone-mod](https://github.com/chdh/pink-trombone-mod)
(MIT). It produces exactly the same samples as the JavaScript original.

## Open and run it

1. Install **Godot 4.3 or newer** (the normal version, not ".NET") from
   [godotengine.org](https://godotengine.org/download).
2. Get this repo onto your computer with **GitHub Desktop** (File > Clone repository).
   On a Mac, avoid "Download ZIP": macOS blocks the engine file that comes in the zip.
3. Open Godot, click **Import**, and pick `project/project.godot` inside the repo.
   If Godot offers to upgrade the project to your version, say yes.
4. Press **F5** (or the play button, top right).

You don't need a compiler: the engine files in `project/bin/` are built by GitHub.

## Controls

- **Tongue**: drag the round marker inside the shaded pad.
- **Constrictions**: click and hold anywhere in the mouth. Near the roof makes
  hissing sounds ("s", "sh", "f"); above the roof closes it ("t", "p", "k" when released).
- **Nose**: click above the line under the nose to open the velum ("m", "n").
- **Pitch**: the strip at the bottom. Left/right is pitch, up/down is how tense the voice is.
- **always voice** / **pitch wobble** buttons turn those off and on.

## What's where

| Path | What it is |
| --- | --- |
| `project/` | The Godot project. `voicebox.gd` draws the tract and handles the mouse. |
| `project/bin/` | The compiled engine for Mac, Windows, Linux and web (made by GitHub, don't edit). |
| `src/synth/` | The voice engine in plain C++ (no Godot code), ported file by file from pink-trombone-mod. |
| `src/pink_trombone.cpp` | Makes the engine usable from GDScript as the `PinkTrombone` class. |
| `tools/` | Checks the C++ port against the original JavaScript. |

## For programmers

### Using the engine from GDScript

```gdscript
var synth = ClassDB.instantiate("PinkTrombone")   # or PinkTrombone.new()
synth.setup(AudioServer.get_mix_rate())
# each frame, with an AudioStreamGenerator playing:
synth.fill(player.get_stream_playback())
```

Controls: `frequency` (Hz), `tenseness` (0-1), `voice_held`, `always_voice`,
`auto_wobble`, `vibrato_amount`, `velum_open`, `volume`, `set_tongue(index, diameter)`,
`touch_start/touch_move/touch_end(id, index, diameter)`. Tract positions use the
original's units: `index` runs from the throat (0) to the lips (~39), `diameter` is
the distance in from the roof (0 = touching the roof, negative = above it).
`generate(frames)` returns raw samples without a player. For drawing:
`get_diameters()`, `get_nose_diameters()`, `get_amplitudes()`, `get_nose_amplitudes()`.

### Building the engine yourself

GitHub does this on every push that touches `src/` (see `.github/workflows/build.yml`:
it builds, runs `project/tests/smoke_test.gd` in a headless Godot, and commits the
results to `project/bin/`). To build locally you need Python, SCons and a C++ compiler:

```sh
git submodule update --init
pip install scons
scons target=template_debug          # copies the result into project/bin/<platform>/
```

### Checking the port against the original

```sh
g++ -O2 -std=c++17 -Isrc tools/render_test.cpp src/synth/*.cpp -o render_test
./render_test tools/scenario.json out          # writes out.f32 and out.wav
npm i esbuild
node tools/compare_js.mjs <pink-trombone-mod>/src tools/scenario.json out.f32
```

Both sides use the same seeded random numbers, so the output should match exactly
(`max diff 0`).

## Licence

MIT, see `LICENSE.md`. Pink Trombone by Neil Thapen; TypeScript version by
Christian d'Heureuse. Do not copy code from zakaton's pink-trombone ports,
which are GPL-3.0.
