# Fixed architectural fittings: approved 2026-10-21 batch

## Built and promoted

One coordinated batch adds restrained maintenance details to the existing authored wing. It does not add rooms, props, usable doors, structural openings, artificial water surfaces or simulation emitters. Production GLBs were promoted and imported at approximately 22:18 UTC; the geometry is frozen pending native image review.

- Main hall: four 96 mm-diameter basin return covers, one 320 × 150 mm waterline skimmer face and one 780 × 620 mm closed tiled maintenance cover on the existing north dado.
- Terrace: four 84 mm-diameter shallow-basin return covers and one matching waterline skimmer face. The roof aperture and all existing terrace construction are unchanged.
- Sidepool: two return covers and one skimmer face, plus a built-in west bench. The finished seat is 450 mm above the 520 mm deck, 580 mm deep and 3.2 m long; 1.87 m of deck remains clear between its front and the pool coping. Plinth, seat and back meet at their real elevations.
- Arcade: a shallow closed service cabinet with an actual plinth and 1.65 m-high counter. Its front stays behind the existing bench line, clear of the arch pier and north branch. A screw-fastened tiled cover is explicitly non-interactive.
- Ten existing metal grates: nine 12 mm longitudinal ribs per removable panel, 5 mm clear slots, 3 mm panel joints and 6 mm end ties. The ties rest on the unchanged drain channel and preserve the previous upper height. The existing brushed-stainless role is retained.

Return covers project 10 mm, skimmer faces 14 mm and screw-fastened covers at most 26.5 mm. Separate local collision envelopes add only 0.5 mm beyond those closed faces. No old proxy is removed or changed. Fixed metal and dark inserts are grouped by room and finish instead of multiplying individual draw calls.

## Exact preservation

Independent raw-GLB and native `GLTFDocument` comparisons verify the original four-room baseline:

- All 336 original diffuse receivers preserve oriented float32 triangle positions, normals and UV0 exactly, including all 145 existing main-hall bake receivers.
- All 516 original local collision proxies retain their exact arrays and transforms.
- All 440 non-grate original visible meshes retain their exact oriented triangle streams. Only the ten explicitly named existing metal grates change.
- New geometry is limited to 16 visible meshes and 21 small local proxies. Main-hall diffuse receivers become 147, with 65 metal meshes and 11 glazing meshes.
- Catalog and builder hashes are unchanged. The existing 21 main-hall ground/coping/stair/connector proxies remain exact, as do deck 0.52 m, water 0.32 m and all basin and stair heights.

Historical pre-enclosure witnesses are not discarded. The active enclosure audit checks all 377 historical proxies, 284 unmodified historical visuals, exactly six approved historical grate variants and all 30 fitting nodes in the three retained-connector rooms. The terrace's four additional grate changes and seven fitting nodes have their own exact witnesses.

## Sources and checkpoint

The complete generator is `tools/blender/build_formal.py`; its `FittedDetails` helper and four `add_*_fittings()` calls author the batch. Editable sources are the corresponding four files under `tools/blender/source/`, protected from automatic Blender import by `.gdignore`. Runtime continues to use GLB. `tools/blender/proposals/fitted-details.patch` records the exact change against the preceding generator and is historical after promotion, not a patch to apply twice.

The exact previous six GLBs, six Blender sources, generator, manifest, builder/catalog and prior enclosure test are preserved in the ignored checkpoint `output/eight-hour/formal-before-fittings-20261021T2218Z/`. Its `checkpoint.json` pins every saved file. The new changed-file hashes are in `verification/formal-fitted-promotion.json`; named geometry witnesses are in `tests/fixtures/formal_fitted_shape_witnesses.json`.

Final changed GLB hashes:

- Main hall: `3d4089cf0fb3a265765f923d445369a4c086727b782bbbba58c3569c61564bf1`
- Arcade: `16a754dfa23add0348ccf79d8af820c60a8ca6f47671da9c1fb430ca535d779c`
- Sidepool: `62a5ad82ae0be9442b4b5536deff0d3359bb7afc58f119ada31346764eebb91f`
- Terrace: `ee57f122e8908fd988c1a3a9f7581bc6089834f87f058f72f2351ce4de9245fc`

The curved bath and standalone arch remain byte-identical to the previous checkpoint. Existing receiver geometry is preserved, but UV2 was repacked and the complete scene manifest changed. The native bake candidate and terrain/optical caches must be regenerated against these exact live hashes, not reused from the old scene.

## Verified, and still awaiting visual acceptance

Before promotion, the dedicated detail audit passed 113,807 checks, including 24,316 UV2 triangles with no positive-area overlaps and 148 exact metre-space ceramic edge witnesses. Independent native import confirms all original receiver/proxy identities. The full 52-leg connected loop, 80 connector escape attempts and curved-water/depth suite passed on the staged assets.

After production import, the main-hall contract passed 330,619 checks, the expansion asset contract 353,931, and the strict historical-enclosure contract 40,595. Both daylight/material and expansion-light contracts passed. The fitting-contact suite passes 53 checks: four real capsule walks past the new bench/cabinet remain grounded, visible furniture stops the capsule at the correct front, and all 15 cover faces have their measured small collision envelopes.

Reproduce the dedicated geometry comparison with `tests/formal_fitted_detail_contract.py`, providing `--baseline-dir output/eight-hour/formal-before-fittings-20261021T2218Z/assets/models/formal`, `--candidate-dir assets/models/formal` and a JSON `--report` path. The independent CPU-native comparison is `tests/formal_fitted_native_compare.gd`, which takes those two directories and a report path after `--`. `tests/formal_fitted_circulation.gd` exercises the production builder and player controller. Use writable HOME/XDG directories when running Godot in a sandbox.

The lightweight `tests/formal_fitted_source_contract.py` additionally passes 84 checks without launching Blender or Godot. It verifies every pinned promoted source/asset hash, all 17 pre-fitting checkpoint files, exact reconstruction of the generator change from its historical patch, and the unchanged structural-authoring syntax tree after removing only the four fitting callbacks and the explicit grate/detail additions. The generator's manifest literal equals the shipped manifest exactly. Its report is `verification/formal-fitted-source-contract.json`. This source/provenance evidence is separate from the clean Blender rebuild below; the old `formal-clean-rebuild.json` is retained unchanged as the earlier enclosure checkpoint.

### Independent rebuild and editable-source proof

Blender 4.3.2 rebuilt all six assets from an exact copy of the delivered generator in an isolated scratch root, limited to two CPU threads. All six GLBs are **byte-for-byte identical** to production. The generated manifest has exactly the same parsed keys and values; its object-key order and final newline differ, so it is correctly reported as semantic identity rather than byte identity.

Separately, `tools/blender/formal_source_roundtrip.py` reopened all six delivered `.blend` files and exported them without executing the generator or saving any source scene. All six exports are again byte-identical to production. This proves that the editable scenes themselves retain the shipped geometry, material roles, normals, both UV channels, proxy topology and transforms. Their metric units, hidden collision metadata and UV-layer presence are also checked directly in Blender. Native `.blend` container hashes are recorded separately and are not conflated with exported geometry identity.

`tests/formal_clean_rebuild_compare.py` records this result in `verification/formal-fitted-clean-rebuild.json`. All 16 active model, editable-source, generator, catalog and builder files retained their previous hashes throughout both runs. Scratch-only negative controls confirm that the semantic fallback accepts an exporter-label-only change but rejects a changed collision vertex or UV0 value. No production model was regenerated or overwritten, no editor import was needed and no GPU was used.

To reproduce without touching production, run `python3 -B tools/blender/verify_formal_delivery.py --work-root /tmp/formal-delivery-check` with an empty directory outside this project. It creates the pre-run SHA-256 snapshot, performs both serial two-thread Blender jobs and invokes the strict comparison. Add `--compare-existing` to recheck a completed scratch run without relaunching Blender. The lower-level comparison accepts `--rebuilt-root` and `--source-roundtrip-dir`. Raw logs from the verified delivery run are `output/eight-hour/formal-fitted-clean-rebuild.log` and `formal-fitted-editable-roundtrip.log`.

The editable-source packaging preflight retains all six scenes, the matching model manifest, all generator/comparison/floor-plan dependencies and the project provenance notices. It rejects Blender backup/interrupted-save/physics-cache artifacts in both release profiles. See `verification/formal-source-packaging.json` and [the delivery guide](../tools/blender/FORMAL_ASSETS.md). Final archive hashes and the union of split source parts remain release-pipeline checks, separate from this source-selection preflight.

The actual native `output/eight-hour/formal-terrace-05.png` shows the promoted narrow-slot drains, small basin returns and waterline skimmer. In that view the fittings remain restrained, rail bases and coping contacts read coherently, and no new doorway obstruction or obvious geometric gap is visible. Its capture metadata records terrace coordinate `(0, -2)`, five rooms, seed `250821`, camera `(0, 2.15, -57)` and 62-degree field of view. Water and dark-soffit readability remain separate lighting/optics acceptance questions, not grounds for changing the frozen geometry.

The actual `formal-exposure-walk-production02-exposure-{1p12,2p2,3p2}.png` production-SDFGI comparison supports mainhall-only exposure 3.2: arch thickness, coping, stair nosings, rail mounts and the real north corridor become more readable without visibly washing out the sunlit floor. The triplet retains the same camera and frozen source state, but is 1280 × 720; it does not prove 1080p fine-detail or continuous-motion quality. Dark ceiling bands and pale, low-depth clerestory backgrounds remain. The attempted native walk stopped after 32 of 144 frames, so this is still-image acceptance only.

The experimental cold-start baked-lighting candidate produced no game image and is not part of this visual acceptance. Production retains procedural sky/SDFGI. The sidepool bench, arcade cabinet and curved bath still need their own actual close/interior views. Geometry/import/circulation and reproducibility proofs do not certify those rendered results. Active assets remain frozen. The image hashes and independent review limits are recorded in `verification/formal-native-visual-review.json`.
