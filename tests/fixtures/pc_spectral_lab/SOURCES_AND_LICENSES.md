# Source references and license scope

This research bundle preserves project-specific work and original notices. It
does **not** relicense the entire bundle as MIT or assert a new redistribution
grant for the owner's original project. See the included original `CREDITS.md`.
That credits file describes a broader game delivery; its asset/package claims
are not an inventory of this narrowly scoped research archive.

## Original caustic source and port

- Original project: https://github.com/YBZSG/beyond-the-basin
- Audited source commit: `66a4543602d9e774db07c2da12ce1d40d522532c`.
- Original modules: `app/pool-vct/water-system.ts` and `water-optics.ts`, copied
  from the existing local provenance snapshot, not downloaded for this task.
- Port audit: included `docs/audit/source-caustics-port.md`.
- Exact current source inputs: `source_manifest.json` and their bundled files.
  These hashes describe the assignment baseline, not byte equality to upstream.

The existing provenance subset has no top-level original-project LICENSE, and
its package.json is private with no license field. This absence is not a grant.
Keep use within the owner's authorized research/project context unless any
broader distribution rights have been independently established.

## Included third-party notices

- `docs/SOURCE_LIQUID_LICENSES.md` preserves the MIT notices for Splash MLS-MPM,
  Three.js (including the tiny DFG/BRDF source data) and three-mesh-bvh.
- `docs/audit/source-caustics-third-party-license.txt` preserves Garrett Johnson's
  three-mesh-bvh MIT notice used by the caustic ray intersection port.
- `source_provenance/beyond-the-basin-66a4543/ATTRIBUTIONS.md` and
  `THIRD_PARTY_THREE_LICENSE.txt` preserve original source attribution.
- `docs/licenses/GODOT_LICENSE.txt` is included as the engine reference notice.
  No Godot executable, export template or engine third-party binary is bundled.
- Python, NumPy and Pillow are external execution/analysis prerequisites, not
  vendored libraries. No package install is performed by the fixture.

The separate `native/source_water/LICENSE` applies to its separate C extension;
that extension is not bundled or needed here and its license is not repurposed
as a blanket license for these files.

## Optical references

Three representative vacuum wavelengths are 650/550/450nm. Previously verified
Daimon/Masumura water data at 20 C gives n=1.331666595718179 / 1.334683329053798 /
1.3396084494078662; air is approximated as n=1 and legacy source water n=1.333.

- Daimon and Masumura, Applied Optics 46(18), 3811 (2007):
  https://opg.optica.org/ao/abstract.cfm?uri=ao-46-18-3811
- IAPWS refractive-index release R9-97:
  https://iapws.org/documents/release/Rindex.download

Only references and numeric constants are provided, not copies of published
papers. Three wavelengths with source RGB tint are not a calibrated lamp
spectrum, RGB-to-spectrum conversion or a full spectral rendering model.
