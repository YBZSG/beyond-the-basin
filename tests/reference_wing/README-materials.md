# New reference-wing material validation

## Source and headless checks

    python tests/reference_wing/test_materials.py
    python tests/reference_wing/validate_materials.py --blender blender --output /absolute/evidence-directory
    blender -b --factory-startup --python-exit-code 1 --python tests/reference_wing/blender_material_contract.py

The second command creates a small disposable staging project; it does not
import the whole game, change the player's profile or start the world. It uses
official Godot's headless dummy renderer. Tests check source legacy hashes,
mathematical gradients, negative-UV hash repeat, generated include identity,
maps/alpha mip coverage, high-precision normal agreement, role isolation,
material switching and CPU decoding of actual imported compressed maps.
It also parse-checks the graphical lab without executing it. Runtime glaze/dry
role palettes and the independent 0.26 dry finish are covered. This is not a GPU
sampling or shader-execution test.
The Blender command only builds/checks node graphs: all role palettes,
roughness locking, physical pitch/joint dimensions, common scaled texture
coordinates, glTF V phase and tangent-normal orientation. It does not render,
export or save a `.blend`. Satin roles explicitly use 0.15/0.20 m tiles and
0.34/0.40 roughness without changing the ref-5 or colonnade 0.10 m roles.
The explicit ref5 crown role additionally checks profile1 isolation and its
unchanged reviewed normal/hash; cyan-only palette roles check linear face/
grout gain parity and preservation of every unrelated existing node graph.
`test_crown_candidate.py` checks analytic derivatives, physical bounds and
exact equality between the reviewed field and the scoped production profile.

## Actual material laboratory, NR OFF

The six cases are the actual legacy art pearl, four baseline ablations, and
the dedicated `ref_tile_pearl_ref5_crown`. Capture metadata records both role
and profile; it does not relabel generic pearl as the accepted scoped profile.

After normal project assets are imported, and only with an available authorized
graphical device:

    godot --path . --rendering-method forward_plus --rendering-driver vulkan --script tests/reference_wing/material_lab.gd -- --reference-material-out=/absolute/output

This lab never starts gameplay, the original water simulation or native APIs.
NR and post filters are absent. A fixed two-wall/floor fixture contains three
modelled emissive strips and an orange geometric object. It captures the actual
legacy art-pearl material, a new neutral control at legacy roughness, shape-only,
roughness-only and the combined new candidate, using fixed close/grazing/distant
cameras and an eight-step lateral sequence. The diagnostic variants are only
lab-local new resources. Palette variants can be checked after selecting shape.

The default lab deliberately uses probe-only reflections, matching the source
scene's SSR-off limitation. An explicit `--reference-material-ssr` enables a
separate SSR-assisted experiment; do not merge those results. Both use the
stock reflection probe and are **not native NVIDIA evidence**. Compare images
at the same camera, exposure and reflected source position, with NR off.

Visual criteria: recognizable strip width/shape inside faces, coherent offsets
or bending at cell boundaries, rough recessed joints, no whole-wall mirror,
no sparkling noisy normals, no persistent motion smear. Geometry/albedo edges
being sharp alone does not pass. Capture the latest real scene material binding
as well as the lab before accepting. Low-resolution probes may limit the result
even when the material is correct.

On the matching NVIDIA build, run the same fixture with genuine RT material
conversion and record executed RT/RR dispatch, shader success and guide buffers.
The pinned engine's grazing-normal clamp and missing coat lobe remain unchanged.
Compare NR off/on only after selecting the PBR candidate; additional NR layers
are not material geometry. Native testing and visual acceptance remain pending
until actual logs/images exist. No Godot, Blender or headless test may be
represented as that missing native validation.

Optional single strong-face trial contract (after generating the QA normal):

    python tests/reference_wing/validate_materials.py --blender blender --candidate-normal output/reference_wing/stair/qa_face_shape_1_8_normal.png --output /absolute/evidence-directory

This additionally checks that only pearl receives the transient Blender normal,
roughness and other roles remain intact, and defaults can be restored. It still
does not render. This rejected trial is QA-only: `strong_face` is not a runtime
variant and the factory explicitly rejects it. The default remains `combined`,
and the original six shaders are untouched.
