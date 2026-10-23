# Reflection temporal synchronization fix

## Observed defect

The first six-second native walkthrough had a genuine integration defect: moving-camera reflections alternated between different apparent alignments. It was not attributed to the user's computer or relabelled as normal waves.

The SubViewport texture updated in the current draw, while `texture_matrix` was committed only in `RenderingServer.frame_post_draw`. Godot sorts child viewports before parents, so the main water shader consumed the new image with the previous projection matrix. The original default `interval=1` also captured only every other idle frame, alternating a mismatched capture frame with a matched/stale frame.

Engine sources: [viewport sort](https://raw.githubusercontent.com/godotengine/godot/4.6/servers/rendering/renderer_viewport.cpp), [frame_post_draw](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-signal-frame-post-draw).

## Correction

`SourcePlanarReflection.update()` now publishes the matrix when it schedules the matching image, before the main material binding. The post-draw callback only marks readiness/completion. Default capture is every frame. A moving or turning camera, or a changed projection, forces a fresh matched capture even if a lower-quality stationary refresh interval is selected. A skipped stationary capture keeps both the prior matrix and prior image together. Mirror TAA is explicitly disabled; main-view TAA and the source wave/normal equations are unchanged. No blur was added.

## Controlled native experiment

`tests/source_planar_motion_test.gd` renders known red/blue boxes over flat, still water. The main camera sees only the reflective water, translates 0.12 m and turns each rendered frame. TAA/MSAA are disabled only in this diagnostic. Expected reflected points are projected geometrically and their rendered color centroids measured.

- Previous every-frame path: maximum alignment error 3.941 pixels, failed the fixture.
- Same-frame pairing alone: maximum 1.1045 pixels, mean about0.600 pixels.
- Same-frame pairing plus motion-forced capture: both refresh0 and refresh1 runs stay within1.1045 pixels, passing the1.5-pixel raster tolerance.
- Stationary-camera, real simulated-wave phase: surface peak reaches nonzero values; sampled image change is nonzero, while the stationary reflection capture may still be throttled. This is not a test that disables all water motion to hide the fault.

Logs and per-frame measurements: `docs/verification/source-planar-motion-before.*`, `source-planar-motion-same-frame.json`, `source-planar-motion-fixed.*`. Initial warmup frames are explicitly excluded from the centroid tolerance because the first reflection has not yet been captured.

The controlled fixture proves this projection synchronization defect and its correction. Subsequent whole-scene footage has now been recorded and checked after the fix: `source-walkthrough-final.mp4` contains 144 actual rendered frames over a six-second continuous walk, wade, turn and stop. The companion `source-walkthrough.json` is from that same take; all 144 incoming occlusion masks are complete. The latest take also includes the static-terrain/prop-spawn correction and 864 wet prop samples, with no dry or fallen props. This is silent offline capture at a fixed 24 Hz simulation/playback rate, not a real-time performance test. It does not claim perfect temporal antialiasing, target-PC frame rate, or ray-traced reflections.

Capture identification: `source-wading-contact.png` is frame 48 of that continuous-input take. `source-wading-disturbance.png` is a separate controlled amplitude-0.32 splash through the real solver/MPM pipeline, not a claim that normal walking produces that splash. Original water, floating-force and direct-wading crest equations remain unchanged. All five final same-process gallery images have now passed decoding and state checks; the strong-impact frame records 13,806 simulated particles and nine liquid composite frames with empty error fields. The final rebuilt PCK also passed an independent `--main-pack` launch outside the project on Linux llvmpipe, with six props, High 768² water, GI, complete masks and both reflection captures ready. It still emits the inherited seven-Texture-RID shutdown warning. See `verification/SOURCE-WATER-STATUS.md`; this is not Windows GPU or Android validation.
