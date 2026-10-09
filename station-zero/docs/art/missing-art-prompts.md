# Missing Art Prompts for Station Zero

Generated with Higgsfield Nano Banana 2 model. All exteriors use the habitat exterior (job ID `9b2fb423-f815-429b-b507-caa72e1c7516`) as the style reference. Interiors are generated with their corresponding existing interior images as style references to maintain camera angle and scale consistency.

---

## BATCH 1: EXTERIOR MODULES

### 1. comms_exterior.png

**Target filename:** `assets/raw/comms_exterior.png`

**Aspect ratio:** 1:1 (1024x1024)

**Style reference:** Habitat exterior (job ID `9b2fb423-f815-429b-b507-caa72e1c7516`)

**Full prompt:**

Smooth 2D game art, top-down isometric view with a subtle 3/4 tilt, Mars colony module. A compact communications station with a sleek gray-metal chassis, white upper access panel with ribbed detailing, dark lower section. Large satellite dish array mounted on top (two to three dishes in brushed aluminum), extending antenna spikes pointing upward. Central sliding door at the base, centered, with cyan-blue accent lights framing the entrance. Small square windows along the dark lower section with cyan internal glow. Side vents and ports indicating active electronics. Light source from upper left, creating subtle shadows on right edges and bottom surfaces. Flat magenta #FF00FF background. Style: Consistent with existing Mars colony modules, functional design, industrial aesthetic, clean lines, weathered metal surfaces. 1024x1024 px.

**Notes for pipeline:**
- Door location: center-bottom, sliding mechanism like habitat (estimated normalized rect ~0.42, 0.68, 0.58, 0.82)
- Accent light color: cyan (#00CCFF or similar)
- Antenna elements should be thin and distinct for animation reference
- Door should be cleanly cut out as separate leaves for animation

---

### 2. archive_exterior.png

**Target filename:** `assets/raw/archive_exterior.png`

**Aspect ratio:** 1:1 (1024x1024)

**Style reference:** Habitat exterior (job ID `9b2fb423-f815-429b-b507-caa72e1c7516`)

**Full prompt:**

Smooth 2D game art, top-down isometric view with a subtle 3/4 tilt, Mars colony module. A solid, compact records and memory archive with a sturdy gray-metal build, white upper section with minimal detailing, dark lower base section. Design emphasizes storage: regular recessed panel sections across the upper surface suggesting sealed storage units, subtle security features (reinforced corners, minimal windows). Central sliding door at base, centered and slightly recessed. Violet-blue accent lights flanking the door entrance. No prominent external hardware or moving parts—quiet, static presence. Light source from upper left, creating defined shadows on right and bottom. Flat magenta #FF00FF background. Style: Consistent with Mars colony architecture, fortress-like stability, clean utilitarian design.

**Notes for pipeline:**
- Door location: center-bottom, sliding (estimated normalized rect ~0.42, 0.68, 0.58, 0.82)
- Accent light color: violet (#9966FF or similar)
- Recessed panel sections should align with grid pattern for consistency
- Storage emphasis in art direction—conveys preservation and records function

---

## BATCH 2: INTERIOR MODULES

### 3. archive_interior.png

**Target filename:** `assets/raw/archive_interior.png`

**Aspect ratio:** 3:2 (1264x848)

**Style reference:** Habitat interior (use existing habitat_interior.png as visual reference for lighting, ceiling panels, and cyan accent lighting)

**Full prompt:**

Smooth 2D game art, top-down interior view of a Mars colony archive module. Functional storage layout with floor-to-ceiling shelving units lining the walls, organized rows of sealed data storage containers and archival boxes in neat sections. Minimal decorative elements; emphasis on preservation and access. Central floor space for movement and records retrieval work. Ceiling features the same dark panel grid as habitat interiors with cyan-blue accent lighting strips along edges and between panels. Steel floor with subtle wear patterns, organized storage zones color-coded by section. Walls in cool gray-blue tones with vertical panel lines. A few illuminated display consoles or reading stations integrated into the shelving. Subtle shadows and depth indicating room volume. Atmosphere: quiet, organized, purposeful. Match the ceiling lighting style and gray background of existing interiors. 1264x848 px.

**Notes for pipeline:**
- Background color: gray (match existing interiors, not magenta)
- Ceiling style: dark panels with cyan lighting strips like habitat interior
- Door should be at bottom-center in a recessed frame
- Shelving should have clear sight lines for character movement
- Consider vault-like quality but not claustrophobic

---

### 4. workshop_interior.png

**Target filename:** `assets/raw/workshop_interior.png`

**Aspect ratio:** 3:2 (1264x848)

**Style reference:** Habitat interior (use existing habitat_interior.png for ceiling treatment and lighting, adapt for workshop function)

**Full prompt:**

Smooth 2D game art, top-down interior view of a Mars colony workshop. Industrial yet organized maker space with workbenches positioned around the perimeter, tool storage walls, a central open floor area for construction projects and assembly work. Overhead crane or gantry rails visible in ceiling framework. Welding stations with red-orange accent glow hints (not bright, subtle), tool racks mounted on walls in orderly rows, power outlets and cable runs along baseboards. Ceiling matches the dark panel grid system with cyan accent lighting and work lights. Steel floor with wear marks from heavy use and material handling. Open, functional layout with good sightlines. Color palette: gray-blue walls, metal surfaces, touches of red-orange for work safety elements. Match the gray background and lighting treatment of existing interior modules. 1264x848 px.

**Notes for pipeline:**
- Background color: gray (match existing interiors)
- Accent light color: red-orange (#FF6633 or similar) subtle glow around welding stations
- Ceiling: dark panels with cyan strips like habitat
- Door: bottom-center in recessed frame
- Tool storage should be visually clear but not cluttered
- Central floor area for construction site visualization
- Gantry/crane suggests scale and construction capability

---

### 5. greenroom_interior.png

**Target filename:** `assets/raw/greenroom_interior.png`

**Aspect ratio:** 3:2 (1264x848)

**Style reference:** Habitat interior (use existing habitat_interior.png for interior structure, adapt for agricultural environment)

**Full prompt:**

Smooth 2D game art, top-down interior view of a Mars colony green room agriculture module. Lush vertical garden with multiple levels of hydroponic and soil-based plant beds, grow lights integrated into upper tiers, rows of healthy green plants visible: leafy vegetables, herbs, and some flowering species. Multiple growing stations with trays, containers, and suspended plant systems creating a dense but organized garden layout. Circulation space between beds for harvesting and maintenance work. Ceiling featuring the standard dark panel grid with grow lights positioned over plant beds (subtle green glow), cyan accent lighting along edges like other modules. Floor in treated material suitable for moisture, with drainage channels visible. Bright, life-filled atmosphere—the most colorful interior. Lush greens contrasting with the gray-blue structure. Match the ceiling lighting style of existing interiors while emphasizing botanical abundance. 1264x848 px.

**Notes for pipeline:**
- Background color: gray (match existing interiors)
- Plant colors: various greens (#2D8F2D, #4CAF50, lighter leaf tones)
- Grow light glow: subtle green-white tint above plants
- Accent lighting: cyan strips like other modules
- Door: bottom-center in recessed frame
- Multiple height levels of growing beds suggests 3D depth
- Water/moisture visible in design (channels, wet surfaces)
- Most visually distinct interior for player recognition

---

### 6. reactor_interior.png

**Target filename:** `assets/raw/reactor_interior.png`

**Aspect ratio:** 3:2 (1264x848)

**Style reference:** Habitat interior (use existing habitat_interior.png for ceiling panels and lighting, adapt for reactor core environment)

**Full prompt:**

Smooth 2D game art, top-down interior view of a Mars colony reactor core chamber. Central massive reactor vessel dominating the space, circular or polygonal in cross-section, dark gray-black with glowing amber-orange center core visible through viewport panel (nuclear reaction glow, intense but contained). Concentric rings of thermal management systems, coolant pipes, and safety structures around the central core. Perimeter control stations and monitoring consoles positioned around the outer edge, with glowing amber accent lights indicating active systems. Overhead infrastructure: dense cable runs, conduit systems, structural support beams visible in the dark panel ceiling. Floor features containment markings and cable pathways. Atmosphere: industrial, powerful, carefully controlled energy source. Amber-orange accents contrasting with dark grays and blacks, subtle shadows suggesting containment structure depth. Match the ceiling panel style with cyan lighting strips along edges plus the amber core glow as the dominant light source. Gray background. 1264x848 px.

**Notes for pipeline:**
- Background color: gray (match existing interiors)
- Core glow: amber-orange (#FFB300 or warm #FFA500) dominant light
- Accent lights: amber-orange around consoles and systems
- Ceiling: dark panels with cyan strips at edges
- Central reactor should be impressive and clearly the power source
- Danger/power communicated through design but not threatening
- Door: bottom-center in recessed frame
- Highly symmetrical layout with core at visual center

---

## BATCH 3: TERRAIN & CHARACTER

### 7. terrain_decals.png

**Target filename:** `assets/raw/terrain_decals.png`

**Aspect ratio:** 1:1 (1024x1024) with 2x2 grid

**Style reference:** Habitat exterior (job ID `9b2fb423-f815-429b-b507-caa72e1c7516`) for surface texture consistency

**Full prompt:**

Smooth 2D game art, top-down view of four separate Mars terrain decals in a 2x2 grid layout on flat magenta background. Each decal fills its 512x512 grid square (about half the canvas), isolated on magenta for clean keying.

**Top-left (512x512):** Frosty ice field patch. Bright white and pale blue ice crystals clustered in an irregular organic patch shape. Frost patterns and crystalline details suggesting frozen water. Subtle shadows from upper-left light. Jagged, natural edges. Not a perfect geometric shape—looks like a patch of exposed ice.

**Top-right (512x512):** Regolith dig pit. Circular or oval excavation in reddish-tan Martian soil. Darker soil exposed at pit edges and bottom, showing depth. Pick marks and tool impressions visible on walls. Loose regolith pebbles scattered around the pit rim. Shows active mining activity—not pristine, shows signs of extraction work. Upper-left lighting creating pit shadow.

**Bottom-left (512x512):** Rock cluster. Group of irregular gray-brown boulders and smaller stones naturally clustered together, varied sizes, scattered arrangement. Weathered surface texture on rocks. Shadows indicating 3D depth and shape. Looks like a natural outcropping or field of rocks.

**Bottom-right (512x512):** Small crater. Circular depression with raised rim, impact-crater appearance. Dark shadowed floor, lighter raised edge. Fine regolith details. Rim texture suggesting compacted soil from impact. Size appropriate for a 4-8 meter diameter Mars crater at game scale.

Each decal is opaque on magenta with clean separation, suitable for sprite-based terrain layer. Flat magenta background. 1024x1024 total with clear grid division.

**Notes for pipeline:**
- Each decal in own 512x512 grid cell, isolated with magenta separation
- Top-left: ice field, bright whites/pale blues
- Top-right: excavation pit, reds/tans/browns with dig marks
- Bottom-left: rock cluster, gray-browns, natural arrangement
- Bottom-right: crater, circular impact form
- All use upper-left lighting for consistency
- Magenta background for clean keying
- Decals will be sliced individually in pipeline

---

### 8. sheet_colonist_sleeping.png

**Target filename:** `assets/raw/sheet_colonist_sleeping.png`

**Aspect ratio:** 1:1 (1024x1024)

**Style reference:** Habitat exterior (job ID `9b2fb423-f815-429b-b507-caa72e1c7516`) for character consistency

**Optional (deferred if time-constrained; fallback is idle front rotated 90 degrees)**

**Full prompt:**

Smooth 2D game art, a single resting colonist figure in sleeping pose on flat magenta background. Figure shown lying down in a bunk or sleeping surface, side-profile or three-quarter view. Wearing the neutral-gray jumpsuit (tintable for role colors). Body relaxed, head on pillow, blanket or covering visible. Face peaceful/resting expression. Hair and skin tone consistent with existing character sheets. Upper-left light direction creating soft shadows under the figure. Full-body pose showing the character at rest, roughly 512x512 px in the frame. Flat magenta background for clean keying. Style consistent with existing colonist character art—smooth, game-ready, clear silhouette.

**Notes for pipeline:**
- Neutral gray jumpsuit (will be tinted per role in asset pipeline)
- Sleeping position clear and recognizable
- Face and hair match existing character sheets
- Size similar to other character poses
- Magenta background for keying
- Note: This is optional and may be deferred; sleeping pose can fall back to idle front rotated 90 degrees if generation time is constrained

---

## Pipeline Checklist

Use this checklist when processing the generated images through the asset pipeline:

- [ ] **All exteriors (comms, archive):** Key magenta, 1px erosion, de-fringe, crop to bbox, scale to ~320px wide
- [ ] **All interiors (archive, workshop, greenroom, reactor):** Key gray background (flood fill from corners), verify outer wall stays opaque, crop, scale to match habitat interior (~1264px wide)
- [ ] **Comms exterior:** Cut door leaves, fill door opening with dark gradient, measure door rect
- [ ] **Archive exterior:** Cut door leaves, fill opening, measure door rect
- [ ] **All exterior modules:** Build masks (accent lights, windows, outline, shadow, gray unfinished, blue ghost)
- [ ] **Terrain decals:** Key magenta, crop each decal individually from the 2x2 grid, save as separate PNGs with grid positions labeled
- [ ] **All buildings:** Verify no magenta fringe, corners are transparent (exteriors) or corners are opaque with outer walls intact (interiors)
- [ ] **Character sheet (if generated):** Key magenta, crop to content, verify can be recolored (low-sat gray pixels)
- [ ] **Run `build_all.py` twice:** Verify byte-identical SHA256 for every output file (determinism check)

---

## Batch Summary

**Batch 1 (Exteriors):** 2 images, 1:1 aspect ratio
- comms_exterior.png with cyan accents
- archive_exterior.png with violet accents

**Batch 2 (Interiors):** 4 images, 3:2 aspect ratio
- archive_interior.png with gray background
- workshop_interior.png with red-orange accents
- greenroom_interior.png with green glow
- reactor_interior.png with amber core glow

**Batch 3 (Special):** 2 images
- terrain_decals.png (required, 2x2 grid)
- sheet_colonist_sleeping.png (optional)

All images use Nano Banana 2 model with style references for consistency. Exteriors reference habitat exterior job; interiors reference their corresponding existing interior images. Flat magenta background for exteriors; gray background for interiors. Light from upper left on all. Generated ready for asset pipeline keying, cropping, and mask building.
