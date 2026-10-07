# Eight new generated wallpaper styles: implementation brief

This is a hand-off for an agent working on macOS. It covers adding eight generated wallpaper
styles to Vibeshed: Flow, Lens, Paper Cut, Automata, Cyclic, Chladni, Complex and Growth. They
were chosen from about 30 candidates that were prototyped in JavaScript and rendered in several
built-in themes.

- `reference.jpg` shows the target look. Each row is one style; the columns are Tokyo Night,
  Gruvbox and Rosé Pine Dawn.
- `prototype/wallpapers.js` is the source of truth for every algorithm, parameter and palette
  mapping. Each style is one `STYLES.<name>` function, written to port line for line onto
  `WallpaperCanvas`.

Port the eight styles to Swift so they look like the reference. Matching pixels is not the goal,
because the prototype's random-number generator differs from `SeededGenerator`.

## Contents

1. [The styles](#the-styles)
2. [Rules from the codebase](#rules-from-the-codebase)
3. [Integration checklist](#integration-checklist)
4. [Translating the prototypes](#translating-the-prototypes)
5. [Style specifications](#style-specifications)
6. [Verification](#verification)
7. [Attribution](#attribution)
8. [Running the prototypes](#running-the-prototypes)

## The styles

| Raw value (config) | Display name | Proposed summary (`WallpaperStyle.summary`) | Proposed SF Symbol | Prototype | Source |
|---|---|---|---|---|---|
| `flow` | Flow | Evenly spaced streamlines through a noise field, tapering where they crowd, around a disc | `wind` | `STYLES.flow` | gart `arts/flowforce/perl`, `gart/flow2/Streamlines.kt`; Jobard & Lefer (1997) |
| `lens` | Lens | Tilted bands and a sun bent around a black hole by a gravitational lens | `camera.aperture` | `STYLES.lens` | gart `arts/sf/src/sf/SF14.kt` |
| `papercut` | Paper Cut | Layered paper sheets with soft shadows, parting around a sun | `square.3.layers.3d.down.right` | `STYLES.papercut` | gart `arts/layers/src/strata/Strata.kt` |
| `automata` | Automata | Panels of elementary cellular automata, each running its own Wolfram rule | `rectangle.split.3x3` | `STYLES.automata` | gart `arts/rule`, `gart/cellular/rule/Rule.kt` |
| `cyclic` | Cyclic | Griffeath's cyclic cellular automaton: noise that organizes itself into square spirals | `arrow.triangle.2.circlepath` | `STYLES.cyclic` | Fisch, Gravner & Griffeath (1991) |
| `chladni` | Chladni | Sand gathering on the still lines of a vibrating plate | `waveform.path` | `STYLES.chladni` | Ernst Chladni (1787) |
| `complex` | Complex | A complex function's phase portrait: zeros and poles become pinwheels | `function` | `STYLES.complex` | Elias Wegert's phase portraits; gart `arts/z` |
| `growth` | Growth | Differential growth: a folding ring drawn at every stage, like brain coral | `brain` | `STYLES.growth` | gart `arts/cell/src/rugae/Rugae.kt` (after Anders Hoff's differential-line) |

The names and icons are proposals. Every icon must exist on macOS 14, because
`testEveryStyleRendersDeterministically` checks it with `NSImage(systemSymbolName:)`. If one
doesn't exist, pick another.

## Rules from the codebase

These come from the code and tests on `main`; read them before writing code.

- **New styles stay out of `auto`.** `WallpaperStyle.varied` is the pool that `auto` picks from,
  by `StableHash.of(slug) % varied.count`. `ClassicMacWallpaperTests.testPeriodPiecesStayOutOfAutomaticPicks`
  asserts `varied.count == 28` ("existing themes keep their automatic style"). Adding to the pool
  would change every theme's automatic wallpaper.
  - Make the eight opt-in: users choose them with `wallpaperStyle:` in config or
    `theme/wallpaperStyle`.
  - Keep `varied` as exactly today's 28 styles, in today's order.
  - One way is a property such as `joinsAutomatic` that is false for the new cases. Another is to
    give `varied` an explicit list.
  - Extend that test to assert the new styles aren't in `varied`.
- **Same seed, same picture.** `testEveryStyleRendersDeterministically` renders every case at
  160×100 twice and compares the bytes. It also checks the icon and that every style looks
  different from every other.
  - Any parallel work must be split into a fixed number of lanes, and each lane must write only its
    own slice. Follow `AttractorDensity` in `WallpaperCanvas+Attractor.swift`: four fixed lanes and
    `DispatchQueue.concurrentPerform`.
  - Randomness must be drawn in a fixed order: sequentially from `rng`, or per lane from seeds
    derived from `rng` before the lanes start.
- **Speed in the debug build.** `make install` ships a debug build, and debug builds don't inline.
  Attractor renders in about 320 ms at 3456×2234 in that build; its commit message records the
  number.
  - Aim for 1 s or less per style at 3456×2234 in debug, measured the same way. Note the timings in
    the commit message or PR.
  - The 160×100 test render must also stay fast. Simulations whose work doesn't depend on the
    output size (Cyclic, Growth, Chladni) must be cheap in absolute terms. Alternatively, scale
    their work with output size while keeping the look.
  - Write hot loops the way `AttractorDensity.trace` does: plain `while` loops, unsafe buffers and
    no allocation per step.
- **Lint limits.** `.swiftlint.yml` warns at 60 lines and errors at 100 for a function body, and
  warns at 500 lines for a file. Split each style into helpers and private types, like the existing
  `WallpaperCanvas+*.swift` files.
- **Formatting.** `.swiftformat` is enforced and CI runs `swiftlint --strict`.
- **No new dependencies.** Everything here needs only Core Graphics, Foundation and Accelerate,
  which `WallpaperRenderer.swift` already imports.
- **Commit style.** Lowercase with a prefix, for example
  `feat: add flow, lens and paper cut wallpaper styles`. Don't bump versions.
- **No project file to edit.** SwiftPM picks up new files under `Vibeshed/`, and the Xcode project
  comes from `project.yml`, which uses folder sources.

## Integration checklist

1. `Vibeshed/Modules/Theme/Wallpaper/WallpaperStyle.swift`
   - Add the eight cases, plus their `displayName`, `summary` and `icon`.
   - Keep them out of `varied`, as described above.
   - Don't mark them `isPixelBitmap` or `isPeriodPiece`. Film grain applies to them like the other
     generative styles.
2. `WallpaperRenderer.swift`: add the eight entries to `painters`.
3. New files, one per family, following `WallpaperCanvas+Plotter.swift`. Suggested split:
   - `WallpaperCanvas+Flow.swift`: Flow, with the streamline placer as a private type.
   - `WallpaperCanvas+Optics.swift`: Lens and Complex, both per-pixel fields on four lanes.
   - `WallpaperCanvas+PaperCut.swift`: Paper Cut.
   - `WallpaperCanvas+Automata.swift`: Automata and Cyclic.
   - `WallpaperCanvas+Physics.swift`: Chladni.
   - `WallpaperCanvas+Growth.swift`: Growth.

   Each file starts with the doc comment the existing ones use: one paragraph on what it paints.
   Each `paintX()` gets a doc comment in the same voice as the other styles.
4. Tests:
   - `VibeshedTests/ThemeEngineTests.swift`: add the new styles to the list in
     `testSeedChangesVariation`.
   - `testEveryStyleRendersDeterministically` covers them automatically.
   - `ClassicMacWallpaperTests.swift`: assert the new styles aren't in `varied` and keep the 28.
   - Add a few small unit tests for pure parts, as the Penrose and Hitomezashi tests do:
     - The first rows of Rule 30 from a single cell.
     - Streamline placement: no two lines closer than `dTest`.
     - A Chladni grain run ends with most grains where |f| is small.
5. Docs:
   - `README.md`: "one of 37 styles" becomes 45, in the target table and in the paragraph that
     lists the styles. Add a clause for the eight and say they're opt-in, not part of `auto`.
   - `config.example.yaml`: add the eight raw values to the `wallpaperStyle` list in the `theme:`
     section, around line 471.
6. Remove `plans/wallpaper-styles/` in the last commit of the implementation PR, unless the
   maintainer asks to keep the prototypes.

## Translating the prototypes

| Prototype (JS) | Swift (`WallpaperCanvas`) |
|---|---|
| `w.enterUnitSpace()`: canvas scaled so the height is 1000 units, y down | `enterUnitSpace()`: same space (it flips Core Graphics so y points down from the top) |
| `w.unitWidth`, `w.unit`, `w.width`/`w.height` (device px) | `unitWidth`, `unit`, `width`/`height` |
| `w.base`, `w.surface`, `w.harmony(n)`, `w.muted(c, a)`, `w.isDark` | the same names |
| `p.foreground`, `p.accent`, `p.background`, `p.red`, … | `palette.foreground`, `palette.accent`, … |
| `c.mix(o, a)`, `Color.white/black`, `c.hsl.h` | `ThemeColor.mix(_:_:)`, `.white/.black`, `hsl.hue` (degrees) |
| `c.css(alpha)` | `color.cgColor(alpha:)` |
| `rng.between(a, b)`, `rng.int(n)`, `rng.pick(xs)`, `rng.unit()`, `rng.bool()` | `rng.between`, `rng.int(below:)`, `rng.pick`, `rng.unit()`, `rng.unit() < 0.5` |
| `w.noise.fractal(x, y, octaves)` | `noise.fractal(_:_:octaves:)`, same construction (the prototype's lattice hash differs) |
| `rampOf([colors])(t)` | write a small helper: piecewise-linear mix over the stops |
| `cycling(xs, i)` | `Array.cycling(_:)` |
| `ImageData` per-pixel loops, then `putImageData` | fill an RGBX `[UInt8]` (row 0 at the top), then `bitmapImage(columns:rows:pixels:)` and `context.draw(image, in: rect)` |
| `blitBuffer(w, buf, cols, rows)`: small buffer drawn smoothed to full size | `bitmapImage` drawn into `rect` with `interpolationQuality = .high` (the default the canvas sets) |
| `ctx.shadowColor/Blur/OffsetY` | `context.setShadow(offset:blur:color:)`. Offset and blur are in device space, not the current transform, so multiply unit values by `unit`. Canvas `shadowBlur` is about 2σ; tune against the reference. |
| `ctx.createLinearGradient` + fill | clip to the path, then the existing `linear(_:from:to:)` helper or `drawLinearGradient` |
| `ctx.arc`/`ctx.ellipse` | `CGMutablePath.addEllipse(in:)`, or `addArc` with care: in unit space y points down, so clockwise flags read reversed |
| `ctx.roundRect` | `CGPath(roundedRect:cornerWidth:cornerHeight:transform:)` |

Each prototype function also reads an optional `w.<style><Param>` override, such as
`w.cyclicRule` or `w.complexFn`. Those let the prototype harness force one variant; they aren't
part of the design and can be dropped.

## Style specifications

Numbers are in units (the canvas is 1000 units tall) unless they say px. "h0, h1, …" means
`harmony(n)`: the accent first, then the palette hues nearest to it. "far" means the last entry of
`harmony(7)`, the hue farthest from the accent.

### Flow (`flow`)

**What it draws:** a calm field of evenly spaced, tapering streamlines across the whole screen,
with a disc. Lines below the disc pass in front of it.

1. **Field.** Angle θ(x, y) = swirl + (fbm(x·f + ox, y·f + oy, 3 octaves) − 0.5)·2π·turns, where:
   - f ∈ [0.0009, 0.0014] per unit;
   - turns ∈ [0.9, 1.3];
   - swirl ∈ [0, 2π);
   - offsets ox, oy ∈ [0, 500).
2. **Placement.** Evenly spaced streamlines (Jobard & Lefer), ported in `streamlines()` from gart's
   `flow2/Streamlines.kt`:
   - dSep ∈ [12, 15], dTest = dSep / 2, step 1.5 with RK2, minimum length 2·dSep.
   - The area extends 2·dSep beyond the frame on every side.
   - A spacing grid with dSep cells.
   - New seeds go dSep to both sides of every point of every accepted line. When none are left, a
     shuffled grid of cover seeds fills any gaps.
   - A line ignores its own points within 2·dTest along it.
   - Each point gets a clearance (nearest other line, capped at dSep) and a taper of
     `clamp((clearance − dTest) / (dSep − dTest), 0, 1)`.
3. **Drawing.**
   - Lines are drawn in order of the y of their middle point.
   - t = cos(midX·k + φ)·0.5 + 0.5, with k ∈ [0.006, 0.012]. Line width = dSep·lerp(0.18, 0.82, t).
   - Color follows t through the ramp [muted(h2, 0.45), muted(h1, 0.2), h0, h0 mixed 35% toward
     the foreground].
   - Each line is a filled outline whose width at each point is `width·max(taper^0.6, 0.12)`, with
     round end caps (`ribbon()`).
   - One line in six is drawn as beads instead: dots every 1.25·width, radius
     0.5·width·max(taper, 0.3), alpha 0.45.
4. **Disc.**
   - Radius ∈ [95, 135], center x ∈ [0.22, 0.78]·W and y ∈ [0.38, 0.68]·H.
   - Fill: the foreground on dark themes, the foreground mixed 10% toward the background on light
     ones. Ring: 18 units of `base` at radius r + 9.
   - It's drawn the moment the sorted lines first pass its center y.
5. **Cost.** About 0.35 s in Chromium; placement dominates. Use flat arrays and integer grid
   buckets.

### Lens (`lens`)

**What it draws:** a per-pixel picture of tilted stripes and a sun behind a gravitational lens. You
see the sun twice: a long arc outside the Einstein ring and a short one inside. A black disc covers
the singularity.

1. **Parameters.**
   - Einstein radius e = 240·unit·[0.85, 1.15] px.
   - Lens center x ∈ [0.3, 0.7]·W, y ∈ [0.32, 0.68]·H.
   - Hole radius 0.38·e.
   - Sun offset ∈ [0.3, 0.7]·e at a random angle; sun radius 0.31·e.
   - Stripes: pitch 31 units, duty 0.32, tilt ±[18°, 42°], random phase.
2. **Per pixel** (see `STYLES.lens`):
   - Deflect the sample toward the lens by e²/r.
   - Use the Jacobian to get the stripe frequency in periods per pixel. Box-filter the stripe
     analytically over that width (`stripe()`), which gives one-pixel-soft edges without
     supersampling.
   - Use the same stretch to antialias the sun's edge.
   - Composite ground → stripe ink → sun → hole.
3. **Colors.**
   - Ground: `base`. Ink: the foreground mixed 18% (dark) or 10% (light) toward `base`. Sun: the
     accent.
   - Hole: `base` on dark themes, the ink color on light themes (it should always read as a black
     hole).
4. **Swift.** Compute the RGBX rows across four fixed lanes, then draw one bitmap. Full device
   resolution is required. Cost: about 0.45 s single-threaded in Chromium.

### Paper Cut (`papercut`)

**What it draws:** cut-paper sheets hanging from the top with soft drop shadows. Four darker
"lower" sheets sit behind a gradient sun, and five "upper" sheets in front. The deepest front sheet
cuts across the top of the sun.

1. **Hues.** If the accent is warm (hue below 75° or above 320°), the sheets take the nearest cool
   harmony hue and the sun takes the accent. Otherwise the sheets take the accent and the sun takes
   orange (red if orange is the same color as yellow). sheet2 is the next cool harmony hue.
   - Sun gradient: [sun mixed 55% toward yellow (and 12% toward white on dark themes), sun, sun
     mixed 45% toward red and 8% toward black].
2. **Sheet colors.** t runs over the layers, 0 for the front.
   - Dark themes: upper = sheet→sheet2 (t·0.6) mixed toward `base` by lerp(0.08, 0.62, t); lower =
     sheet2→sheet (t·0.4) mixed toward `base` by lerp(0.42, 0.66, t).
   - Light themes: upper mixes toward the background by lerp(0.72, 0.15, t); lower mixes toward
     black by lerp(0.15, 0.32, t).
   - Every sheet is filled with a diagonal gradient [lighten 3.85%, color, darken 7%] at
     [0, 0.52, 1].
3. **Edges.**
   - 12 anchors span the width plus 18% on each side. Each anchor's y = mean + amplitude·(−cos(2π(u − crest)) + 0.16·sin(4π(u − 0.35·crest + phase))) + jitter.
   - The anchors share part of their jitter across layers. Smooth them with a clamped uniform cubic
     B-spline at 24 samples per segment (`bSpline()`), then close the shape to above the top edge.
   - Parameters:
     - gap ≈ 95·[0.9, 1.1];
     - wave ∈ [150, 195];
     - crest ∈ [0.25, 0.75];
     - drift ∈ ±0.02;
     - opening ∈ [0.44, 0.52]·H.
   - Lower sheets: mean = opening + 0.28·gap + layer·gap, amplitude wave·(0.64 + 0.12·t).
   - Upper sheets: mean = opening − (4 − layer)·gap, amplitude wave·(0.34 + 0.66·t). Draw both from
     back to front.
4. **Shadows.**
   - Offset y 16.4 units, blur ≈ 2·16.4 units. Alpha 0.46 on dark themes, 0.3 on light ones.
   - Shadow color: near-black on dark themes; on light ones, the sheet color mixed 60% toward black.
5. **Sun.**
   - Vertical radius ry ∈ [0.16, 0.2]·H; horizontal radius ry·[1.0, 1.12]; tilt ±24°.
   - Center x = W·(crest ± 0.04); center y = opening·H − wave + ry·[0.35, 0.7]. This puts it just
     under the deepest front sheet, where that sheet rides highest.
   - Drop shadow, then two faint warm highlight bands clipped to the disc.
6. **Ground.** A gradient under everything: sheet2 mixed 80% toward `base` → `base` darkened 30% on
   dark themes; sheet2 darkened 35% → 50% on light ones.
7. **Cost.** Cheap: about 20 filled paths.

### Automata (`automata`)

**What it draws:** a Mondrian-like layout of panels. Each panel is filled with a different
elementary cellular automaton in two tones.

1. **Layout.** Start from the full canvas and run three passes. Each pass splits every rect that is
   at least 4·gap wide and tall into four, at random multiples of gap (gap = 97.66).
2. **Rules.**
   - 3-cell: 30, 45, 73, 86, 89, 105, 110, 124, 135, 150, 54, 57.
   - 5-cell: 838, 209218, 774857, 37788005, 22047073, 1069090987.
   - The lookup is bit v of the rule number for neighborhood value v, most significant bit on the
     left. Start from a random row, wrap the edges, and skip the first 40 generations.
3. **Drawing.**
   - Cells are 4 units. Panels have a 7-unit gutter in the frame color: `base` darkened 30% on dark
     themes, the background on light ones.
   - "On" cells: a random hue from harmony(5), darkened 10% on light themes. "Off" cells: another
     random hue, muted 0.78 on dark themes or 15% over the background on light ones.
4. **Swift.** Build one small bitmap per panel and draw it with `interpolationQuality = .none`.
   That's faster than one rect per cell.

### Cyclic (`cyclic`)

**What it draws:** a cyclic cellular automaton grown from noise until spirals take over, shown in
crisp cells.

1. **Grid.** 4-unit cells (about 400×250), wrapping at the edges.
2. **Rules.** A cell in state s becomes (s + 1) mod N when at least `threshold` neighbors are
   already in state s + 1.
   - "spirals": von Neumann range 1, threshold 1, N = 14, 420 steps. Picked two times out of three.
     It gives the square Greek-key spirals in the reference.
   - "cca": Moore range 1, threshold 1, N = 14, 900 steps.
   - The prototype also defines "squarish", which isn't used. Don't port it.
3. **Colors.** A ring of four tones, crossfaded smoothly over the 14 states:
   - dark themes: [h0, muted(h1, 0.25), `base` mixed 12% toward h0, muted(h2, 0.3)];
   - light themes: [h0 mixed 15% toward the background, h1 mixed 45%, the background, h2 mixed 40%].
4. **Cost.** About 1.2 s in Chromium for "spirals" and about 3 s for "cca". In Swift:
   - Use `UInt8` double buffers and precomputed neighbor offsets.
   - Split each step's rows across four lanes; this is deterministic because the buffers are
     double.
   - Stop early on the first neighbor match.
   - If "cca" can't meet the budget, keep only "spirals".

### Chladni (`chladni`)

**What it draws:** fine lines of sand on an invisible plate, with knots of sand where lines cross,
plus a sprinkle of accent grains.

1. **Plate.** f(x, y) = cos(nπx)·cos(mπy) ± cos(mπx)·cos(nπy), with x ∈ [0, W/H] and y ∈ [0, 1].
   n and m are in [2, 7] and differ; the sign is random.
2. **Grains.** The prototype uses 700,000 grains at uniform random positions and runs 80 steps:
   - p −= 0.0008·f·∇f, plus a uniform shake of ±0.0014·min(|f|, 1) on each axis;
   - then clamp to the plate.

   The prototype takes the gradient by finite differences (h = 1e-3). In Swift, use the analytic
   gradient, which shares the cosines with f.
3. **Drawing.**
   - Background: `base`.
   - Grains are 1.3 px squares (at least 0.9 units) in the foreground, mixed 15% toward h0 on dark
     themes. Alpha is 0.5 on dark themes and 0.45 on light ones.
   - Every 19th grain is redrawn in the accent at 1.4× size and alpha 0.85.
4. **Cost.** The prototype takes about 11 s, so this needs the most care. In Swift:
   - Use the analytic gradient.
   - Split the grains across four lanes, each with its own `SeededGenerator` seeded from `rng`
     before the lanes start.
   - Plot grains into a bitmap (alpha-composited counts per pixel) instead of making 700,000 Core
     Graphics calls.
   - Try 250,000–400,000 grains and 50–60 steps, and check the lines are still well defined
     against the reference.
   - Grain count can scale with pixel area, which keeps the 160×100 test fast.

### Complex (`complex`)

**What it draws:** a soft per-pixel field. The argument of f(z) goes once around a ring of palette
colors, log|f| adds shaded bands, and faint lines mark the phase. Zeros and poles become pinwheels.

1. **Functions** (pick one per seed):
   - "rational": (z² − 1)(z − 2 − i)² / (z² + 2 + 2i), span 3.2;
   - "sinc": sin z / z, span 9;
   - "roots": (z⁵ − 1) / (z² + 0.4 + 0.3i), span 2.4.

   The prototype's "sinpoly" was dropped because it aliases. The screen covers `span` vertically,
   centered at a random offset of ±0.3·span horizontally and ±0.2·span vertically.
2. **Color.**
   - t = arg/2π + 0.5 is looked up in a 512-entry ring:
     - dark themes: [h0, muted(h1, 0.2), muted(h2, 0.35), muted(h3, 0.2)];
     - light themes: [h0 mixed 20% toward the background, h1 35%, h2 50%, h3 35%].
   - band = frac(log₂|f|); shade = 0.72 + 0.28·smoothstep(0, 0.92, band) − 0.28·smoothstep(0.92, 1, band).
   - Twelve phase lines: shade ×= 1 − 0.08·(1 − smoothstep(0, 0.06, frac(12t))). The prototype
     multiplies in an extra factor that always equals 1; drop it.
   - Output: lerp(`base`, ring color, shade) on dark themes; lerp(`base`, ring color, 0.35 + 0.65·shade)
     on light ones.
3. **Swift.** Per pixel on four lanes, at full resolution: the band edges and phase lines need it.
   About 0.8 s single-threaded in Chromium.

### Growth (`growth`)

**What it draws:** gart's Rugae. A closed ring of nodes grows into a folded, brain-coral blob, and
every fifth stage is drawn as a closed line, so the layers read as relief.

1. **Simulation** (s = 1000/1200; constants from `Rugae.kt`):
   - **Start:** 50 nodes on an ellipse of radius (46–50)·s, 1.6 times wider than tall, centered at
     x ∈ [0.4, 0.6]·W and y ∈ [0.45, 0.55]·H.
   - **Forces per step:**
     - pull toward the midpoint of the two neighbors (0.45);
     - push from every node within RAD = 44·s, except neighbors up to two steps along the ring:
       1.2·(1 − d/RAD)/d, found with a spatial grid of RAD cells;
     - a random nudge of ±0.12;
     - soft walls 40·s from the edges.

     Then clamp each node's move to 1.9·s.
   - **Splitting:** split every edge longer than 9·s. Then pick about n/40 random edges and split
     each with probability food²·1.6, where food = fbm(midpoint·0.0042/s, 2 octaves).
   - **Limits:** 950 steps, at most 9,000 nodes, and a snapshot every 5 steps.
2. **Drawing.**
   - Every snapshot is a closed path; the palette sweeps twice from oldest to newest. The 5-stop
     ramp (dark themes) is [muted(h1, 0.45), h0, muted(h2, 0.1), h3, muted(h1, 0.45)]; light themes
     use the background and black mixes from the prototype.
   - Alpha runs 0.6 → 1 and width 1.0 → 1.5 units. The final ring is in the foreground at 1.7 units.
3. **Cost.** The heaviest of the eight: about 19 s in Chromium. In Swift:
   - Use flat `Float` arrays and counting-sort grid buckets rebuilt each step, with no allocation
     per step.
   - Compute forces across four lanes, reading positions and writing each lane's own range. Draw the
     brownian nudges sequentially beforehand so the result is deterministic.
   - If it's still over budget, cut steps (to about 600), the node cap (about 6,000) or the snapshot
     count, and check the relief still reads.
   - Report the timing. If Growth can't get near the budget, raise it with the maintainer rather
     than shipping a slow style.

## Verification

1. Run `swift build`, `swift test` and `make lint`; all must pass. CI runs the same on
   pull requests.
2. **Visual check.**
   - Render each new style with `WallpaperRenderer.draw(palette, size:choice:)` at 2560×1600. Use
     Tokyo Night, Gruvbox and Rosé Pine Dawn (`BuiltInThemes.tokyoNight`, `.gruvbox`,
     `.rosePineDawn`) and a few seeds; a throwaway test that writes PNGs to a temporary folder is
     enough.
   - Compare against `reference.jpg`. Check dark and light themes, a few different seeds, and the
     160×100 thumbnail size.
3. **Timing.** Time each style in the debug build at 3456×2234, as the attractor commit did, and
   list the numbers in the PR.
4. **In the app.** Run `make run-debug`, then use `theme/wallpaperStyle` to browse each new style
   with live preview.

## Attribution

Flow, Lens, Paper Cut, Automata and Growth are adapted from **gart** by Igor Spasić
(https://github.com/igr/gart), which is under the BSD 2-Clause License:

- Put a credit line in the header comment of each Swift file that ports them, for example
  `Adapted from gart (https://github.com/igr/gart), © 2022 Igor Spasić, BSD 2-Clause License.`
- Add gart's license text, which is in the gart repository's `LICENSE`, to a
  `THIRD_PARTY_NOTICES.md` at the repository root. Vibeshed itself stays MIT.

Cyclic, Chladni and Complex follow published mathematics and physics and need no notice. Cite the
source in a doc comment, as the existing styles do. For example, Pulsar's doc comment cites Peter
Saville's *Unknown Pleasures* cover.

## Running the prototypes

`prototype/` is self-contained and needs no build:

- **Interactive:** run `python3 -m http.server` inside `prototype/`, then open
  `http://localhost:8000/?style=flow&theme=tokyoNight`. Pick any style, any built-in theme
  (`themes.json`), any size and a variation number; the variation works like
  `theme/shuffleWallpaper`.
- **Batch to PNG:** run
  `npm i playwright && npx playwright install chromium`
  once, then
  `node render.mjs flow,lens tokyoNight,gruvbox,rosePineDawn 2560 1600 [variation]`.
  Output goes to `prototype/out/`, which is not tracked.

The prototype seeds each render from FNV-1a of `"<theme slug>:<variation>"` with a mulberry32 RNG.
Swift seeds from `StableHash.of(theme.slug) &+ variation` with SplitMix64, so the same theme gives a
different, equally valid composition.
