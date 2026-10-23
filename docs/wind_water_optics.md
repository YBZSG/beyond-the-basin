# PC wind ripples: model and boundaries

The optional wind layer adds the analytical derivatives of three directional height modes to the original surface normal. That normal is used by the existing Fresnel, planar-reflection distortion, screen-space refraction and highlight calculations. No scrolling normal-map texture is introduced.

## Bounded control

- Default strength 0.18, propagation direction 35 degrees, density 1.
- Direction is where crests travel in world X/Z coordinates, not the meteorological direction wind comes from. 0 degrees is +X, 90 degrees is +Z.
- Strength uses a nonlinear response: approximately 0.73 mm total equivalent relief at the default, at most 6 mm at strength 1. This is optical relief, not a mesh-height or collision change.
- Three base wavelengths are 0.48, 0.23 and 0.115 metres, divided by density 0.5–2. Pixel-footprint filtering suppresses unresolved frequencies; very fine modes may disappear at a distance instead of sparkling.
- Gravity/capillary-inspired phase rates are deliberately scaled for slow indoor motion. This is an art-directed optical approximation, not a simulated wind field or complete wind/water physics.
- Strength, direction and density ease independently. Phase is integrated rather than multiplied by an editable speed and elapsed time. Changes of wave vector compensate phase around the player's position. 359 to 1 degrees takes the short path.
- Closing the menu resumes the existing game clock. Controls save their desired values; the rendered state eases toward them after play resumes. Off and zero strength fade out, then reach exact zero. Existing interaction ripples are not disabled.

## Unchanged systems

The original shallow-water solver, detail ripple field, MPM particles, photon caustics, depth/collision queries and player/prop forces are unchanged. Wind settings do not reconfigure or rebind those systems. Runtime wind work consists of a bounded three-mode CPU parameter update and shader uniforms. Each publication owns a fresh three-element parameter snapshot, because Godot retains PackedArray references; previously submitted uniforms are never mutated in place. There is no extra per-frame GPU readback, queue, snapshot or wait.

The wind layer does not generate wind-driven buoyancy, spray, coastal waves, air-flow occlusion or new photon caustic patterns. It is evaluated only on existing water surfaces, with a shallow-water fade; it does not transport a disturbance through a wall or connect separate physical water domains. Existing world-boundary and opaque-depth clipping remain in force.

Android and the mobile preview opt out of the added wind rendering. Existing Android artifacts are unchanged. This source update is published on the independent Godot branch; the existing binary releases are unchanged.

## Validation interpretation

Controller and settings tests cover time continuity, bounded values, invalid inputs, actual UI callbacks, ConfigFile migration/save/reload, quality retention and exact zero output. Native fixtures use the actual authored hall, source water shader and original GPU solver kernels at a reduced 192-square field and 320-wide planar capture. They are controlled optical tests, not a complete walking game or target Windows performance test. The recorded clip is consecutive fixed-time native samples, not a real-time frame-rate claim.

The source layer remains approximate screen-space refraction plus planar reflection. Existing scene-switch black/green reports are not claimed fixed by this feature. Lighting, geometry and overall photorealism remain separate limitations.
