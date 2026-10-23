# Source-water fog and Android repair

This is a source-based repair of the existing Godot port, not a claim that its visuals now match POOLS or a photoreal final product. The original 66a4543602d9e774db07c2da12ce1d40d522532c scene remains the default; the authored main hall remains a selectable spawn. The held-item wheel direction, dry/wet footstep separation, and original water simulation remain intact.

## Restored original atmosphere

The previous Godot generic fog was not the original implementation. This release ports the original engine.ts Tyndall post pass: 20 samples over 36 m, its source light direction, spreading shaft, drifting density, phase function, room/corruption easing, and opaque-depth occlusion. This is the original screen-depth raymarch, not physically complete volumetric multiple scattering. It cannot see occluders absent from camera depth. A separate exact FogExp2 pass restores source distance attenuation before screen refraction. Low water's fallback fragment receives the same fog once; ordinary water samples already-fogged scene color.

Forward+ and Mobile have different render graphs. The adapter places distance fog before each backend's screen copy and the shafts after transparent water. Forward+ MSAA is retained. Mobile main-view MSAA is unavailable with the depth required by the original splash/fog compositors, so its real AA options are Off, FXAA and SMAA plus render-resolution scaling. Internal source whitewater still uses its own 4x multisample target. Mobile HDR is enabled so native scene color and custom source optical passes share the same linear HDR units.

## Caustic and callback improvements

The original default causticsRefresh=2 updates once per three rendered frames. That can look stepped even when whole-frame rendering is smooth. Desktop High/Ultra now default to every frame; an independent cadence control remains available. Existing explicit advanced-water cadence settings are preserved. Every-frame updating costs more total work than skipped frames, even though each update is cheaper.

The optimized caustic pass caches the exact source wave-height/normal evaluations on their repeated photon-grid lattice. It retains original photon triangle grids, refraction/reflection equations, BVH visibility, radiance, filtering and mip generation. Zero-power outgoing wall photons skip a BVH query that cannot change their output. It is not a fake animated caustic texture.

On cloud llvmpipe, two High-quality 1024-square caustic A/B pairs at t=0 and17.25 produced byte-identical floor/wall targets. Isolated GPU medians were approximately24% lower. This is NOT a whole-game FPS result or a Windows/Android benchmark. The first full-world timing run failed to reach a steady world during its182-second warmup, so its frame-cost comparison is explicitly inconclusive.

Exact SWE half-field CPU extraction also removes redundant per-component script work. CPU-only384-square A/B medians were63.715ms versus35.903ms, with byte-identical fields and exactly equal reductions. Retired asynchronous callbacks no longer overwrite newer physics. This does not change solver timestep, physics cadence or particle caps, and is not proof of target-device frame rate.

## Android

The APK contains the current original SWE, detail waves, photon caustics, APIC-MPM splash and liquid/whitewater shaders, rather than the earlier approximate mobile water. It uses Vulkan Mobile, an arm64 debug/test build, touch controls and independent Low/Medium/High/Ultra settings. A startup capability check reports unsupported compute/storage/attachment requirements instead of silently substituting cheap water. Dimensity9400 was provided as the intended chipset, but no physical phone has been tested here.

High selects SMAA and full-resolution rendering; Ultra adds125% rendering. SDFGI, native SSR, SSAO/SSIL and TAA are not advertised as supported Mobile features. Source planar reflection and source fog are separate custom systems. High quality may remain expensive; choose supported individual settings rather than assume a chipset guarantees performance.

The new local signing identity is only for this requested test APK, not a Play Store identity. No private key is included in source or delivery archives. The APK requests no additional Android permissions. Install and device compatibility remain user-side validation.

## Verification and limits

See docs/SOURCE-VOLUMETRIC-FOG.md, SOURCE-CAUSTIC-PERFORMANCE.md, SOURCE-WAVE-READBACK-PERF.md and docs/MOBILE* for exact methods and source provenance. GPU checks run on Godot4.6.3, cloud llvmpipe Vulkan, not the user's Windows machine or phone. Source physics formulas do not make Godot lighting and reflections identical to the former Three renderer. Native GI, asset polish and target-hardware optimization remain incomplete.

The known seven Texture-RID teardown warning predates this repair; it is not evidence of a new caustic-cache texture allocation (the cache adds a storage buffer). It remains a cleanup issue. No GitHub push or external hosting was performed.

### Current recorded validation

- Final CPU/data regression suite:40 processes passed, zero failures. Separate headless editor import also completed without script errors.
- Forward+ fog pixels:11/11 checks; Mobile fog pixels:11/11 checks. Source optical-expression comparison:4,004 evaluations.
- Real Vulkan Mobile full-world smoke: passed original startup, compute-capability guard, actual source MPM/caustic execution, pause/touch gating, fixed-camera original variant3 fog views and selectable authored-world recreation. This run dispatched180 original MPM steps for6,188 particles and executed5 liquid compositor frames and7 photon updates. It is a correctness fixture with fixed simulation time, not a real-time benchmark.
- Native Mobile capture images read linear RGB half-float data and explicitly convert to sRGB before8-bit PNG encoding. This is necessary display encoding, not an artistic grade.
- Initial/crossing shells now batch immediately while interiors stream. Sixty source fixtures preserve exactly identical final packed positions/normals/UVs and collision counts; intermediate shell draw meshes reduce904→162. This removes an identified temporary draw-call cost, but no target-device startup improvement is claimed without measurement.

Android attachment delivery uses four lossless ZIP containers. Extract all four into the same folder, then run Rebuild-APK.cmd (or the Python equivalent). The reconstruction checks individual parts and the complete APK SHA-256, does not access the network, install anything, or change PowerShell execution policy. Parts cannot be installed separately. Complete APK:46,288,784 bytes; SHA-2568e732159d85618b4ee7c87dce021ff3821be14eb18e9299c2f3f972393095456.
