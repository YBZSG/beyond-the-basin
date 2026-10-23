# Reference-only origin, not the Web application

This Godot-only branch keeps one unchanged authoring input from original commit [66a4543602d9e774db07c2da12ce1d40d522532c](https://github.com/YBZSG/beyond-the-basin/tree/66a4543602d9e774db07c2da12ce1d40d522532c): `beyond-the-basin-66a4543/app/pool-vct/water-optics.ts`.

`tools/source_port/generate_water_surface.py` reads its WATER_FRAGMENT as the historical mechanical translation baseline. The complete, current runtime shader is already included in `shaders/`. Do not run that historical generator over current shaders expecting it to preserve subsequent Godot integration fixes; review its output separately.

The TypeScript input is not executed by Godot and requires no npm installation. Its path is retained to keep the generator's exact input contract. The original Web application, package manifests, browser tests and old parity-oracle tools are deliberately absent. They remain available at the pinned original commit and in prior complete archival deliveries. Original attribution and Three notices are preserved here; additional translated-code licenses are in `docs/SOURCE_LIQUID_LICENSES.md` and `docs/audit/source-caustics-third-party-license.txt`.
