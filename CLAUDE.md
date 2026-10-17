## graphify

There is a knowledge graph at `graphify-out/`, but **it does not cover this project's
code.** graphify has no GDScript support: `.gd` is absent from its `CODE_EXTENSIONS`,
and nothing in the package mentions Godot, `.tscn` or `.tres`. All 19 scripts under
`Scripts/` and every scene are invisible to it.

What the graph actually contains, as of 2026-10-14: 78 nodes and **0 edges** — 64 from
graphify's own skill documentation under `.claude/`, and 14 from the two Python helpers
in `Tools/`. Nothing from the game.

Rules:
- **Do not run `graphify query` for questions about this codebase.** It cannot answer
  them, and returns "No matching nodes found". Read the scripts and scenes directly, or
  grep them.
- `graphify update .` only re-indexes the Python tools, so it is not worth running after
  changing GDScript.
- The graph is still accurate for `Tools/*.py` and the skill docs, if you ever want it.

To make graphify useful here, it would need `.gd` taught to it via tree-sitter — that
means patching the installed package, which an upgrade would wipe. Not done.

## Verifying visual changes

Headless tests prove logic, not placement. For anything positional — tile draw offsets,
hitboxes, collision against art, UI fit — render a frame and measure it; do not derive
it. `Tools/shoot.gd` captures a frame from the house, and `Tools/sweep.py` measures a
tile's true draw position by differencing two renders. A tile's `texture_origin` was got
wrong three times here by reasoning about it instead.

## Godot

Godot is not on PATH. The editor binary lives at
`D:\Applications\Godot 4.7.2\Godot_v4.7.2-stable_mono_win64_console.exe` — use the
`_console` variant for headless CLI work.

- Run a test: `<godot> --headless --path . --script Tools/test_props.gd`
- Re-import assets: `<godot> --headless --path . --import --quit-after 200`

A headless `ResourceSaver.save()` **strips every `uid://`** from the saved file, because
nothing loads the uid cache outside the editor. Check `git diff` after any headless save
that writes a `.tres` or `.tscn`, and restore the uids.

The test suites under `Tools/` (`test_props`, `test_cursor`, `test_interior`,
`test_door`, `test_autotile`) are plain `SceneTree` scripts; run them the same way.
