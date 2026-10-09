# Asset pipeline tests

`test_assets.py` tests the Python asset pipeline (`tools/build_all.py`, spec `docs/specs/sprite-view.md` section 3,
tests P-0 to P-15). It was written before the pipeline, so until `tools/build_all.py` exists every test fails with
`build_all.py not found ...`. That is expected.

Needs Python 3 and Pillow. No pytest, no numpy.

## Run

From the repo root:

    python3 -m unittest discover station-zero/tools/tests -v

From `station-zero/`:

    python3 -m unittest discover tools/tests -v

One class or one test:

    python3 -m unittest discover station-zero/tools/tests -k TestP7Masks -v

If pytest is installed later, `python3 -m pytest station-zero/tools/tests` also works (plain `unittest.TestCase` classes).

## What a run does

1. The first test that needs outputs runs `python3 tools/build_all.py` once (cwd = project root) and caches the result
   for the whole session. If the build fails, every dependent test fails with the build's last output.
2. P-2 runs the build a second time and compares sha256 of every file under `assets/processed/`.
3. Five throw-away builds run in temp copies of the project (`<tmp>/station-zero` plus a sibling
   `<tmp>/station-zero-handoff`, so `pipeline.raw_dirs` resolves as in the repo). The real `assets/` is never touched by them:
   - `syn`: P-0 (raw lookup order, ignored raw is garbage bytes), P-6 forced door-measurement failure (flat archive exterior),
     P-10 magenta-background interior with an enclosed magenta hole, P-9 construction sheet with separators off the 256 grid.
   - `flip`: P-15 three builds in one temp project (no optional raws and no green room exterior, then all dropped into
     `assets/raw`, then removed again); also supplies the synthetic 2x2 fixtures of P-13 (decals) and P-14 (sleeping poses).
4. Temp directories are deleted at exit. One full run is roughly 6 pipeline builds.

## Absent raws

Raws that have not arrived (comms and archive exteriors, 4 interiors, `terrain_decals.png`, `sheet_colonist_sleeping.png`)
are never skipped. `TestAbsentRawsUsePlaceholderPath`, P-11, P-13 and P-14 assert the placeholder path for each one that
`data/art.json` names and that is absent from `raw_dirs` (kinds: a file under `placeholder/`; optionals: `file: null`),
and print the list. P-15 and the fixtures cover the placeholder path even once every raw exists.

## Conventions the pipeline must follow (assumptions of the tests where the spec is silent)

- `build_all.py` derives the project root from its own location (`<root>/tools/build_all.py`), reads `<root>/data/art.json`.
- Manifest `raw` is a path relative to the project root, `door_rect` and `pivot` of building entries are normalized.
- Sheet frame tables are `assets/processed/characters/{jumpsuit,eva,construction}.json` (one per sheet, shared by the 4 jumpsuit roles).
- Sleeping poses record their scale as `scale` on the manifest entries or in `characters/sleeping.json` (must equal the jumpsuit JSON scale).
- Placeholder files live under `assets/processed/placeholder/` (any subfolder) with the same names, e.g. `habitat_base.png`.
- Warnings (door measurement fallback) go to stdout or stderr and contain "warn" and the kind name.
- Manifest entries of the placeholder kinds point at the placeholder file and set `placeholder: true`.

## Where the tests deviate from the spec wording

- P-1 "alpha contains both 0 and 255 for every entry": enforced for base, interiors, atlases, sleeping poses and decals.
  For masks and interior outlines only "contains 0" (the spec's own rules give an empty `none` accent mask and a ghost
  with alpha at most 191); door leaves are only checked to be RGBA.
- P-4 base height is checked within 2 px of an independent approximate keying of the raw (the test does not reproduce the 1 px erosion).
- P-6 split-door leaf: the centre pixel is the seam, so the test samples the centre of each leaf (x at 25 % and 75 %).
- P-8 is inferred from the four role atlases alone (pixels that differ between roles were recolored; pixels equal in all
  four but still suit-gray count as misses), because the pre-recolor gray atlas is not an output.
  The face region is the top 18 % of the opaque box of `idle_front`.
