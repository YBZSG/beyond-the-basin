# Reference-wing CPU surface audit

Run source meshes and cross-check actual GLB positions/areas without rendering, Godot imports, or source edits:

    blender -b -t 2 --python tests/reference_wing/seam_audit/audit_coplanar.py -- --config tests/reference_wing/seam_audit/final_production_config.json colonnade cyan_corridor octagonal_bath ball_lounge stair_gallery

Run a specific immutable candidate with a JSON config mapping a unique report label to `[source_blend, actual_glb, geometry_contract]` paths relative to the project. Pass `-- --config path/to/config.json report_label`.

The script records before/after SHA-256 stability, cross-object plane-intersection areas, opposite-face contacts, exact ray witnesses, metric UV and interpolated corner-normal comparisons, meaningful route/camera exposure versus unproven sample eyes, and source/GLB consistency. Unique-position hash computation normalizes IEEE signed zeros. Final results must not be interpreted as GPU/runtime or complete visual seam acceptance.

`python tests/reference_wing/seam_audit/test_clipping.py` runs eight pure-Python clipping regressions. `summarize_audit.py` packages the original five named reports for review. It describes the baseline48 target set and should be updated before use on post-repair results.

Baseline evidence is preserved under output/reference_wing/seam_audit/baseline_2058. `water_repair_targets.json` provides37 exact pairs and AABB end-trim candidates, with explicit caveats for proxy/visible-surface union preservation. Four room roof/lintel pairs cannot be proven safe from their pair alone and need additional covering-shell evidence or a narrower visual-face operation.

Writes are confined to tests/reference_wing/seam_audit and output/reference_wing/seam_audit. Source .blend files are opened read-only and never saved.
