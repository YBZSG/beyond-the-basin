# Complete-room contact QA

This independent audit reads the editable complete-room Blender sources. It does not run the generator, save a `.blend`, launch Godot, import into Godot, use a GPU, or modify production assets. All output roots must be explicit. Blender 4.3.2 CPU, two threads.

## Run

Run from the candidate project root. Replace `OLD_ROOT`, `NEW_ROOT`, and `QA_ROOT` with absolute paths.

```sh
/usr/bin/blender -b --factory-startup -t 2 --python tools/architecture_contact_qa/audit_blender_contacts.py -- --input-root OLD_ROOT --output-root QA_ROOT/baseline
/usr/bin/blender -b --factory-startup -t 2 --python tools/architecture_contact_qa/audit_blender_contacts.py -- --input-root NEW_ROOT --output-root QA_ROOT/candidate
python tools/architecture_contact_qa/audit_glb_preservation.py --input-root OLD_ROOT --qa-dir QA_ROOT/baseline
python tools/architecture_contact_qa/audit_glb_preservation.py --input-root NEW_ROOT --qa-dir QA_ROOT/candidate
MPLCONFIGDIR=/tmp/architecture-qa-matplotlib XDG_CACHE_HOME=/tmp/architecture-qa-cache python tools/architecture_contact_qa/draw_contact_sections.py --qa-root QA_ROOT
python tools/architecture_contact_qa/write_contact_report.py --qa-root QA_ROOT
```

Optional detailed tiny-edge UV inspection:

```sh
/usr/bin/blender -b --factory-startup -t 2 --python tools/architecture_contact_qa/inspect_uv_edge_outlier.py -- --input NEW_ROOT/tools/blender/poolrooms_wing/source/circular_bath.blend --output QA_ROOT/candidate/uv_edge_outlier.json
```

The section drawings require matplotlib. The independent GLB parser requires NumPy.

## Interpretation

- `gap_m > 0`: air between a sampled real lower mesh surface and receiver.
- `gap_m == 0`: exact geometric bearing.
- `gap_m < 0`: actual receiver contains the lower surface, an embed/overlap. For the submerged Lanes footing bases, `-0.100` is intentional.
- `receiver == null`: no local source receiver along the ray.
- A nominal 2 mm tolerance accommodates tiny bevel-edge samples; flat bearing faces are measured separately in the section geometry.
- A clear opening under a header/roof is not automatically an invalid span. The report differentiates upper members from footing/support samples.
- The hollow middle of an arch is never substituted for a foot region.
- `conditional_neighbor_foundation_contacts` uses the actual floor mesh translated by 32 m. It demonstrates compatible neighboring geometry; it does not claim a running native scene was observed.
- GLB preservation compares all visible triangles after 0.1 mm world-space quantization and checks all authored collision bounds separately. It does not replace native visual or movement QA.

Outputs include the preserved frozen baseline and intermediate pre-jamb-refinement candidate, final sample-level JSON, foot-region CSV, normal/UV checks, geometry hashes, exact section diagrams and the readable QA report.
