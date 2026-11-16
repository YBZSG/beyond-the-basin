# Dusk sky panorama

- Original generated asset using built-in `image_gen.imagegen`, 2026-10-26; no source asset downloads, API/CLI fallback, or borrowed game panorama.
- File: `dusk-sky-panorama.png`; RGB LDR PNG, **1774 × 887**, exact 2:1 aspect. This is not HDR radiance data.
- Reference `01-dusk-athletics-ground.png` was viewed for dusk color and mood only; it was not supplied as an edit input. No landscape geometry is included in the sky texture.
- Intended mapping: 360° × 180° lat-long; horizon at texture midheight; neutral atmospheric lower hemisphere; separate game geometry provides ground and structures.
- Actual measured sun center UV: `(0.370756, 0.493300)`, elevation **+1.206°**. Generator did not obey requested +6° exactly; align scene sun to actual texture. Bright core bounds x=653–663, y=433–442 (zero-based pixels).
- Visual inspection: sky-only, subtle gray-violet cloud ceiling, peach-orange low sunset, no text/terrain/buildings/water/characters. No crop or resize was performed.
- Longitude edge compatibility measured directly on RGB pixels: mean absolute left/right difference 2.31/255 across all rows, 3.42/255 upper hemisphere. Not pixel-perfect seamless: local cloud-edge differences reach 58/255; place seam behind primary reference camera and inspect in-engine.
- Pole rows are approximately uniform rather than mathematically perfect; engine visual verification remains required. No runtime/GPU performance claims.

## Generation prompt

Use case: photorealistic-natural.
Asset type: original production SKY-ONLY equirectangular environment texture for a 3D game PanoramaSkyMaterial, LDR PNG.
Generate exactly a 2:1 aspect ratio image, ideally 2048x1024 or 3072x1536. This is a full 360-degree longitude by 180-degree latitude spherical lat-long panorama, NOT a perspective landscape photograph and NOT a cropped wide photograph. Top edge is zenith (+90 degrees), middle horizontal row is horizon (0 degrees), bottom edge is nadir (-90 degrees). Left and right longitude edges must seamlessly match in color and cloud pattern. Clouds stretch naturally in lat-long projection near poles; top row uniform.
Primary request: an empty, lonely soft dusk sky with subtle realistic atmospheric haze and scattered thin muted violet-gray clouds softly lit peach and orange. Warm softly glowing small orange sun at longitude represented by x=37.5% of width, latitude +6 degrees (y=46.67% of height), approximately 0.7 degree angular diameter, not an enormous disc. Dusk atmosphere reminiscent of a lonely athletics ground at sunset, but show ONLY SKY. Zenith is desaturated violet gray; sunset near front-left warmly orange-peach; opposite horizon softly lavender. Natural quiet subtle detail, no dramatic fantasy clouds or oversaturation.
The ENTIRE lower hemisphere (y>50%) is smooth soft neutral dusty lavender-gray atmospheric fill grading to uniform nadir, NOT ground, NOT reflective water, NO mirrored sky, NO clouds below horizon, NO visible horizon line drawn across. Absolutely no terrain, hills, mountains, land, sea, water, vegetation, trees, sports field, track, bleachers, stadium, architecture, lamps, buildings, figures, birds, text, labels, logos, watermark or framing. Real game geometry is provided separately. Seamless longitude edges and mathematically centered horizon are critical.
