# PoolCore campaign collectible kit

Original procedural artwork authored by the OpenAI assistant for PoolCore, 2026-10-25. Dedicated to the public domain under CC0-1.0: https://creativecommons.org/publicdomain/zero/1.0/ . No purchased assets, downloads, external textures, scans, or third-party model sources were used. Text uses Blender's bundled Bfont, converted to mesh for export.

## Files
- `campaign_collectibles.blend`: editable source with five named collections, intact bevel/normal modifiers, PBR materials, and five root empties.
- `campaign_collectibles.glb`: all five roots at the origin. They intentionally overlap. Instantiate only the desired named root.
- `key.glb`, `fuse.glb`, `valve.glb`, `card.glb`, `diagram.glb`: recommended independent game imports, with matching named roots.
- `validation.json`: evaluated mesh counts, triangles, materials and exact Blender-space bounds.
- Generator: `tools/blender/campaign/build_campaign_collectibles.py`.

## Mounting and scale
Metres, scale 1. Every root is at (0,0,0). In exported glTF/Godot coordinates +Y is the decorated front face, +X is the long axis, and thickness is Y. Mount flat on a shelf without rotation; rotate the root 90 degrees about X for a vertical display. Verify the desired facing direction in game. The key is 15.7 cm long, fuse 13 cm, valve wheel 13.6 cm diameter, card 10.2 cm wide, and diagram sleeve 22.1 cm wide.

Surface materials are moderately rough satin brass, steel, ceramic, polymer and paper. The sleeve uses alpha blending rather than a transmission extension for broad runtime compatibility. As with any transparent mesh, final sorting should be checked under game lighting.

## Rebuild
From repository root:

    blender --background --python tools/blender/campaign/build_campaign_collectibles.py

The generator replaces only this kit's generated files. Blender 4.3.2 was used. Numeric validation and glTF structure checks passed; no render review or in-game visual test was performed for this delivery.
