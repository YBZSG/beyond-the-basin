# Poolrooms free-asset acquisition and integration notes

Verified and downloaded 2026-10-24 UTC. Only the zero-price official downloads were used. No payment, account creation, checkout, bundled executable, or bundled script was used. Assets are for the user's existing private personal Godot project. Do not push or publish raw source assets.

## Official sources and included licenses

- Cenji, Backrooms Level 37-Poolrooms Kit: https://cenjiyt.itch.io/backrooms-level-37-poolrooms
  - Free download: Cenji_BackroomsLevel37_Poolrooms_FREE.zip, 61 GLB + 61 FBX + LICENSE.txt.
  - Actual bundled LICENSE.txt was read before integration. Allows personal/commercial project use and modification; prohibits reselling, redistributing, repackaging, or uploading raw or modified assets as a standalone asset pack. Attribution appreciated, not required.
  - Keep the license in the private project and credit Cenji in project provenance. Do not treat this as CC0 or an unrestricted source-redistribution license. Personal integrated game use is within the stated grant. A standalone asset download or public raw-asset repository is not appropriate. Distribution beyond this user's personal game was not requested and has not been performed.
  - Paid editable Blender SOURCE package was not downloaded.
- The SideQuest Shop, No Diving: Municipal Pool Props: https://thesidequestshop.itch.io/no-diving-municipal-pool-props
  - Free version 3 download: no-diving-municipal-pool-props-free.zip, containing no_diving/pack.glb, pack.fbx, atlas.png, README.md, LICENSE.txt.
  - Actual bundled LICENSE.txt was read. Base pack is CC0 1.0 Universal. The 14 props have a single 1024x1024 palette atlas and opaque/emissive materials.
  - Paid colourways were not downloaded. The base pack's styling is flat-shaded aqua/white/safety orange; use sparingly if targeting realistic empty Poolrooms.

## Technical checks

Blender 4.3.2 CPU import passed for all 62 GLB files. Cenji total geometry: 28,042 triangles across 61 individually exported meshes. No Diving: 16,500 triangles across 14 named meshes in one GLB scene. The scene positions are a showroom arrangement, so individual prop roots must be repositioned before use.

Cenji GLBs contain embedded 512x512 base colour, roughness and normal tile maps. The base-colour texture was visually inspected: 4x4 ceramic tiles per UV unit. UVs are approximately metre-based, so the default texture produces 25 cm tiles. Preserve the original UVs and avoid uncorrected scaling. World/triplanar replacement materials need a 4 tiles/meter scale, not a 4m grid.

Cenji glTF materials are double-sided. All inspected meshes have UVMap. They do not include prebuilt game collision; generate static trimesh collision for architecture where needed and ensure openings remain open. Geometry edges have modest beveling. Curved wall segments and round portal contain actual curved triangulated geometry, not textured rectangles.

Coordinate convention: Godot/glTF Y-up, Blender Z-up. Most wall/floor modules are corner-rooted: Godot x increases from 0 to 4m and z extends negatively from 0. Pillars are centered horizontally. Many pool-specific walls, arches, curved walls and circular portal extend from y=-1.5 to y=3.0 around a deck/water reference at y=0. Do not place them using their bounding-box center or assume a 3m overall height. Dry floors top at y=0; shallow/medium/deep floors top at -.45/-.9/-1.5. Add .52 to source root height if aligning the source deck to an existing y=.52 deck, then adjust submerged geometry separately to the target basin floor as necessary.

Critical passage notes: the circular portal is a closed ring, so its lower edge can create a traversal lip if deck alignment is not checked. Use a walking test or provide a deliberate ramp/step. Avoid flattening all pieces to a common bounding-box height, as this would stretch tiles and reshape openings.

Original three-region composition opportunity: repeated arch/column shallow hall, curved pool gallery through a circular portal, and a deeper stepped pool with bridges. Retain the project's existing water shader instead of importing WTR_01_Surface_4m.

See mesh-inspection.json for complete actual bounds, UV bounds, mesh counts, material/image inventory and triangles. Coordinates there explicitly identify Blender vs Godot axes. See cenji-mesh-gallery.png for a CPU-rendered geometry/UV inspection sheet.

## Archives

- Cenji_BackroomsLevel37_Poolrooms_FREE.zip: 2088212 bytes; SHA-256 1711cf7227be69b6f1d8cb802a16da84351177f5c6ef798104ed74cd72a45c6e

- no-diving-municipal-pool-props-free.zip: 588773 bytes; SHA-256 00d353151b3f4fd3b7778dfa4b833b9ffc81a03628dee61bea3eb19f2ad43f40

## No Diving selection recommendation

Use the original no_diving/pack.glb and select only a few nodes inside integrated rooms. Suggested static shore props: bench_hooks (1 x 1.545 x .3 m), pool_ladder (.614 x 1.505 x .407 m), float_stack (.888 x .274 x .421 m). Dimensions are Godot X/Y/Z. These share pack_opaque, a 1024x1024 atlas, roughness .82, metallic 0. The free pack is stylized, so avoid overfurnishing the liminal architecture. No ring-shaped life buoy was verified; float_stack is the available named float prop. Do not replace or alter existing floating-object physics. Original source meshes carry showroom translations that should be replaced by desired scene positions, not added to them. See no-diving-prop-inventory.json. No separately repackaged prop bundle is provided.

Opening ray checks are in opening-clearances.json. Circular portal centerline opening is approximately y=-.64..2.04; at y=0 its usable width is2.30m, at y=1.80 it is1.56m. Wide arch09 opening is about2.98m wide at deck and2.69m high in the center. Results use ray samples spaced1cm and source-local coordinates. These do not replace capsule traversal validation in the final game.
