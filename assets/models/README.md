# Quiet Wing: editable Blender model handoff

These four self-contained glTF 2.0 binary files contain the project's original,
procedurally authored geometry. No downloaded model, external image, font, or
texture is included or required.

## Files

- **quiet-wing-oculus-court.glb**: 923,664 bytes; 282 editable mesh objects; 60,752 triangles. 天光环庭 (OCULUS COURT).
- **quiet-wing-vaulted-lap-hall.glb**: 194,604 bytes; 167 editable mesh objects; 11,394 triangles. 穹顶泳廊 (VAULTED LAP HALL).
- **quiet-wing-changing-gallery.glb**: 73,360 bytes; 278 editable mesh objects; 10,556 triangles. 更衣回廊 (CHANGING GALLERY).
- **quiet-wing-prop-kit.glb**: 98,660 bytes; 39 editable mesh objects; 5,116 triangles.

The prop kit contains four separately grouped assemblies: slatted bench, square
drain grate, stainless shower with its own drain, and wall-mounted rescue ring.
They are arranged side by side. Each assembly has a named parent; reset that
parent's location to zero to place it at the origin before reuse.

## Ownership and licensing

These models are original additions authored for this project, with no downloaded
third-party model components. This handoff does not impose a new license on the
original repository or claim it is public domain; the project owner chooses its
redistribution license. The separately supplied scan textures retain their CC0
license and are not embedded in these GLBs.

## Import in Blender

1. Choose File > Import > glTF 2.0 (.glb/.gltf).
2. Select one of the files above.
3. Use the Outliner to select named parts or whole prop parents. Geometry is
   deliberately not merged or decimated: mesh pieces, transforms, materials,
   authored arch names, and assemblies remain editable.

One source unit is one metre. The GLBs use glTF's Y-up convention; Blender's
importer converts them to Blender's Z-up coordinates. Room interiors use the
same origin as the 32 m procedural room cell. The basin deck top is y = 0.52 m
in the source; the props in the kit have their attachment/base level at y = 0.

## Scope and visual differences from the running game

- The three room exports are **interior architecture kits**, not complete room
  shells. They include the authored terraces, steps, vaults/arcades/oculus,
  benches, lockers, plumbing, rails, ladders, and fittings present in each room.
- The engine-owned shared basin floor, outer portal walls, shared ceiling,
  water surface/simulation, lights, environment, fog, and gameplay physics are
  not exported. The authored vault, annular oculus, and coffer beams are present.
- Static base colours, roughness, and metalness follow engine.ts, including its
  brushed stainless fitting material. The live procedural tile/grout shader,
  wetness, reflection tracing, water caustics, and other runtime effects are
  **not baked into textures or geometry**. Build Blender materials and lighting
  if you want a matching offline render.
- The game's CC0 scanned maps are supplied separately in
  public/textures/ceramic/ with their source/license notice. They are not embedded
  in these GLBs: the engine uses world-space projection at a 4 m repeat, not
  each part's local glTF UV layout.
- Sign boards retain their original size, position, board colour, and Chinese
  label in glTF extras/custom properties. Canvas lettering and borders are not
  baked; the boards therefore import without visible printed lettering.
- Objects with existing authored names retain them. Generic source boxes and
  rods receive descriptive names for easier selection.
- These are modelling exports only. Editing a GLB does not modify the live game;
  implement the corresponding changes in app/pool-vct/curated-wing.ts to change its generation.

## Regenerate and validate

From the repository root, with the project's existing dependencies installed:

```sh
node --experimental-strip-types scripts/export-quiet-wing.mjs
```

Requires Node 22.13 or later. No Blender installation is needed to export.
The script validates every GLB header, chunk and buffer/accessor byte bounds,
finite geometry and PBR factors, and absence of texture/external-buffer
dependencies. It also imports each GLB through Three's GLTFLoader and checks
world bounds and triangle counts against the original authored geometry.

See manifest.json for exact byte sizes, object counts, triangle counts, bounds,
and validation results. An optional blender-validation.json, when provided,
records a separate headless Blender import check. All generated files live in
the repository's ignored output/models directory.

## V4 complete baked room

The separate Blender Bake Source archive includes `oculus-room.glb` with the complete static room shell and dedicated nonoverlapping UV0. It is not the same file as the editable interior kit above. The log PNG is irradiance, not albedo: decode its RGB values to linear HDR according to the supplied manifest before applying a Lambert diffuse material. For Blender inspection use the included .blend / linear HDR and reproduction scripts. Runtime world-coordinate scanned ceramic, live water, direct lighting, specular probes and interaction still belong to the game engine. The baked geometry uses authored corner normals, not normals recalculated from welded triangles.
