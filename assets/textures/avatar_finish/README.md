# Optional original cloth finish

This folder is an unintegrated candidate, not a replacement for the frozen Pool Explorer V2. Its separate `avatar_finish_candidate.glb` adds only metre-scaled cloth UV2/tangents and necessary seam vertex splits. Geometry, original UV0/albedo, skin weights, rest bones, animations and non-cloth surfaces remain exact.

The four PNGs are original analytic 512-square seamless data maps. Use OpenGL +Y normals, no sRGB conversion for normal/roughness, repeat filtering and mipmaps. Nominal yarn pitch is 0.70 mm shirt / 0.80 mm trousers. These are subtle lit PBR details, not a photoreal-character upgrade.

Use the reversible `scripts/player/avatar_finish_candidate.gd` helper only with this metric-UV candidate. Do not blindly assign the maps to the frozen V2's stretched UVs. There is no automatic water-darkening or wetness integration.

Editable formulas, cloth-only Blend UV source, canonical geometry/rig checks, exact scale evidence, native A/B runner and integration proposal are in `tools/blender/avatar_finish/README.md`. The separately named edited-source roundtrip test GLB lives only in the ignored tools/audit directory, not this runtime candidate folder.
