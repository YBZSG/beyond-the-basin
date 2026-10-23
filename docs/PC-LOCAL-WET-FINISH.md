# Local wet-finish experiment: disabled by default

The low-arched bath's local thin-film material experiment is **OFF by default**. To inspect it explicitly, launch Godot with the user argument `--pc-local-wet-finish`, for example after the engine's `--` separator. Omitting that exact flag returns the existing shared bath materials; `--pc-local-wet-finish=false` does not enable it. This is not a saved graphics preference and is not advertised as an accepted visual improvement.

Only variant 12 / `low_arched_bath`, and only its deck and tiled wainscot material clones, can opt in. The shower's coat-free dry clone remains dry in both modes. The weak receiver registry remains active so local clones receive the current photon textures, source-domain origin and wall extents without retaining unloaded rooms. Shader math, source water/solver/photon math, geometry and lighting are unchanged by the default-off revision.

## Native evidence and limitation

The earlier enabled candidate completed the native `wet-finish-05` full-water readiness, body and ordinary grab checks with no reported errors. It produced a local pool-edge highlight, **not convincing evidence of a wetter overall atmosphere**. The deck is mostly edge-on in that water-level view.

The commanded route/view matched the baseline, but the camera positions differed by 0.281 mm and the basis maximum absolute delta was 0.000043. Source water remained live. Consequently this is not an exact-pose, static-frame material comparison; temporal water differences cannot be attributed to the material. The effect remains an opaque ceramic roughness / thin-film approximation, not geometric puddles or layered water optics.

## Narrow CPU regression

`tests/pc_local_wet_finish_opt_in.gd` tests actual builder material selection across five module identities and five material roles. Run headlessly with no user flags, then with `-- --pc-local-wet-finish --expect-enabled`, and optionally `-- --pc-local-wet-finish=false --near-match`.

The isolated Godot 4.6.3 checks passed: default OFF 86, exact opt-in 90, near-match OFF 86. They verify role/module scope, original resource identity by default, unique local clones, source immutability, correct room origin, unchanged shower coating and receiver registration. They do not constitute new GPU or native visual acceptance. Detailed reports and the native comparison are in the retained candidate evidence directory.
