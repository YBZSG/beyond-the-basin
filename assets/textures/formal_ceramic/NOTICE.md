# Formal hall analytic ceramic

These three PBR maps are original, deterministically authored project material assets. They are not a photogrammetry scan, a vendor photograph, or a modified Poly Haven scan. They introduce no third-party asset license. The original CC0 Poly Haven images remain unchanged one folder above.

Regenerate with `python tools/materials/build_formal_ceramic.py` (NumPy and Pillow). See `material_manifest.json` for physical dimensions, channels and checksums.

The 4096² atlas contains 16 × 16 tiles over 1.6 × 1.6 metres: 100 mm pitch, 1.8 mm grout, 0.6 mm eased edges, 0.28 mm recess and only 8 μm of face crown. 4K resolves the narrow joints and edge transitions without pretending increased resolution alone creates realism. The normal is OpenGL +Y. Albedo has no illumination, AO, caustics or painted highlights. The scalar RGB surface texture is linear, not sRGB: roughness, batch variation, coverage.
