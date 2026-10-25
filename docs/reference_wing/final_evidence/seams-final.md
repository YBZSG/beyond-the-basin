# Final production surface audit

Status: PASS for the bounded coplanar-repair target.

Freshly scanned all five production sources and parsed their actual final GLBs. All 48 original camera/route-visible duplicate-surface pairs remain absent. Zero remaining camera/route-visible same-facing overlaps and zero sampled shading conflicts.

## Per-scene results

- colonnade: 9/9 original targets removed; 0 trusted-view overlaps; 9 retained outside/buried/unconfirmed-view contacts. Production GLB SHA-256: b932ef1f37c33e4c57e19ad1a7b649e851c850cd8e386f7c5192ba86799987e7.
- cyan_corridor: 18/18 original targets removed; 0 trusted-view overlaps; 18 retained outside/buried/unconfirmed-view contacts. Production GLB SHA-256: b0f78182f23c223c95116f02f5d529fa830eaad99c2e12d12eed1e434d855765.
- octagonal_bath: 10/10 original targets removed; 0 trusted-view overlaps; 17 retained outside/buried/unconfirmed-view contacts. Production GLB SHA-256: c2cff5a4851fa1cda186b023a32afe7c36489f1f84cf7da4363c73482f1ae20e.
- ball_lounge: 11/11 original targets removed; 0 trusted-view overlaps; 17 retained outside/buried/unconfirmed-view contacts. Production GLB SHA-256: 039f9d43f92cdb0c2f75fbe540e4d82f57476b18f331bd4f958ce0fd4ab6f24f.
- stair_gallery: 0/0 original targets removed; 0 trusted-view overlaps; 2 retained outside/buried/unconfirmed-view contacts. Production GLB SHA-256: 6ef6e82d7a9d39dc3139afd2b01bde572e2af3d2ec2ef15538830d204ba862db.

All files stayed unchanged throughout each scan and still match the final freeze. All source/GLB unique-position signatures match; source/GLB total-area differences are zero or floating triangulation tolerance. Each report and production file hash is recorded in FINAL_PRODUCTION_AUDIT.json.

## Retained contacts, not concealed

63 same-facing object-pair contacts remain: colonnade9, cyan18, bath17, lounge17, stair2. All water residuals have no sampled exposure. Lounge has four outside module corners and five rear porthole reveal/backing contacts seen only from unproven outside/foundation eyes, plus eight unexposed contacts. Stair retains two threshold/far-wall foundation contacts, with one below-floor witness from an unproven foundation eye, not the intended player routes.
Opposite-facing structural contacts are tracked separately and not counted as z-fighting. Shared zero-area triangle edges and ordinary ball contacts are not defects in this audit.

## Evidence

- FINAL_PRODUCTION_AUDIT.json: complete final manifest, result hashes, exact retained pairs and limitations.
- Per-scene *_coplanar.json: exact source face intersections, area, planes, ray witnesses, UV/normal/material checks and current source/export hashes.
- baseline_2058/: original failed/exposed findings, preserved.
- Eight pure-Python clipping regression cases passed.

## Limits

- This is evaluated-source cross-object exact-coplanar geometry and controlled BVH ray exposure, with actual GLB buffer position/area consistency checks, not GPU/render/runtime appearance acceptance.
- Source/GLB unique positions and areas match; their signatures are supporting surface consistency evidence, not a general formal topology equality proof.
- Retained outside/buried/occluded or unproven-view contacts remain; no blanket zero-overlap or no-seams claim.
- Plane tolerance1e-5m, minimum positive area1e-7m². Two-offset normal/plane broadphase plus exact clipping, not a near-coincident/noncoplanar intersection search.
- Authored camera and contract-route eyes are meaningful samples, not every possible player view.
- Does not independently certify all structural supports, material roughness, refraction, caustics, water clarity, or controller traversal.
- No Godot import, rendering, production mutation, or GPU operation was performed.
