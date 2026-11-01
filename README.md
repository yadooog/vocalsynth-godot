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

## Working together

The repo is private, so friends need an invite first:

1. The owner opens **Settings > Collaborators** on GitHub
   (github.com/yadooog/vocalsynth-godot/settings/access), clicks **Add people** and types
   each friend's GitHub username. They accept the invite from their email or GitHub.
2. Each friend follows **Open and run it** above.

Day to day, in GitHub Desktop:

- **Fetch / Pull** before you start, so you have everyone's latest work.
- Make a change, test it with F5, then **Commit to main** with a short note and **Push**.
- Try not to edit the same scene (`.tscn`) as someone else at the same time. Godot rewrites
  whole scene files, so two people's changes to one scene clash. Scripts (`.gd`) merge fine.
- If GitHub Desktop says there's a conflict, stop and ask whoever made the other change.
- After someone changes the C++ engine (`src/`), GitHub rebuilds it in about 25 minutes
  and commits the new files to `project/bin/`. Pull again once that's done.

Every push to main also updates the web version on the `web-build` branch (about 3 minutes).
A quick automatic test runs first, and if it fails the GitHub **Actions** tab shows why.

## Controls

- **Walk**: WASD / arrow keys, or press and drag in the room. Scroll to zoom.
- **Control pad** (bottom left): drag the tongue in its slice, press along the tube to close
  it, the **pitch** pad (left/right note, up tense, down breathy), the **mouth** pad (lips and
  jaw) and the **size** slider (small squeaky voice to big low one). Sound plays while you
  touch it.
- **Timeline** (bottom right): **record** or **+ key** to make a 4-second phrase, **space**
  plays it. With a key selected, the control pad edits that key.
- **Say box and boards** (under the control pad): type something to say it. The **‹ ›** arrows
  switch between two boards: **sounds** (+ saves the control pad, names up to 3 letters) and
  **phrases** (+ saves the whole timeline, scrolls). Right-click a pad to rename or remove it.
  In the booth, phrases and the say box are greyed out.
- **The stage**: the drums play there; stand on it to edit the beat. **loop on beat** repeats
  your phrase in time with the drums.
- **The booth** (left of the stage): walk in to make your section of the song. Press **done**
  and you're revealed on the stage, then your section joins the song with its own singer.
- **?** (top left) lists the keyboard shortcuts.

## What's where

| Path | What it is |
| --- | --- |
| `project/character/` | The character: `character.gd` (body, head shape, neck physics, googly eyes, tongue) and its two shaders. |
| `project/` | The Godot project. `main.tscn`/`main.gd` lay out the screen and connect everything; `voicebox.gd` is the tract, `xy_pad.gd` the pads and slider, `timeline.gd` the phrase editor. |
| `project/room/` | The hub room (`world.gd` layout and walking, `room.gd` builds it), the drums (`beats.gd`) and the beat grid. |
| `project/song/` | The shared song: each section from the booth plays on its own voice with a singer. |
| `project/theme.tres` | The paper look, made by `tools/make_theme.py` (edit that, then run it). |
| `project/bin/` | The compiled engine for Mac, Windows, Linux and web (made by GitHub, don't edit). |
| `src/synth/` | The voice engine in plain C++ (no Godot code), ported file by file from pink-trombone-mod. |
| `src/pink_trombone.cpp` | Makes the engine usable from GDScript as the `PinkTrombone` class. |
| `tools/` | Checks the C++ port against the original JavaScript. |

## For programmers

### Using the engine from GDScript

```gdscript
var synth = ClassDB.instantiate("PinkTrombone")   # or PinkTrombone.new()
synth.setup(AudioServer.get_mix_rate())
$AudioStreamPlayer.stream = synth.create_stream()  # plays on Godot's audio thread
$AudioStreamPlayer.play()
```

All methods are safe to call from the game while the audio thread is running.
(`fill(playback)` still works for an `AudioStreamGenerator`, but adds lag.)

Controls: `frequency` (Hz), `tenseness` (0-1), `voice_held`, `always_voice`,
`auto_wobble`, `vibrato_amount`, `velum_open` (hum), `voice_size` (1 = original,
0.5 tiny, 2 giant), `jaw` (0-1, 0.5 = original), `lips` (0 closed, 1 original, ~1.4 spread),
`volume`, `set_tongue(index, diameter)`,
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
(`max diff 0`). The extras (voice size, jaw, lips) are off at their default values,
so the check still covers the core engine.

## Licence

MIT, see `LICENSE.md`. Pink Trombone by Neil Thapen; TypeScript version by
Christian d'Heureuse. Do not copy code from zakaton's pink-trombone ports,
which are GPL-3.0.
