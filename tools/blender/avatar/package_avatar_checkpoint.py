"""Package only original editable-avatar deliverables, never the full game or caches."""
from pathlib import Path
import hashlib, json, zipfile
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'tools/blender/avatar/delivery'
OUT.mkdir(exist_ok=True)
paths = []
for pattern in [
    'assets/models/avatar/*.glb', 'assets/models/avatar/*.png',
    'assets/models/avatar/*.json', 'assets/models/avatar/*.md',
    'tools/blender/avatar/*.py', 'tools/blender/avatar/reference_prompt.txt',
    'tools/blender/avatar/pool_explorer.blend', 'tools/blender/avatar/avatar_evidence_versions.json',
    'tools/blender/avatar/final_test_*.json', 'tools/blender/avatar/final_test_*.log', 'tools/blender/avatar/final_visual_parse.log',
    'tools/blender/avatar/previews/explorer_preview_idle.png',
    'tools/blender/avatar/previews/explorer_preview_walk.png',
    'scripts/player/pool_avatar.gd', 'scripts/player/pool_avatar.gd.uid',
    'shaders/avatar_body.gdshader', 'shaders/avatar_body.gdshader.uid',
    'tests/avatar*.gd', 'tests/avatar*.gd.uid',
]:
    paths.extend(ROOT.glob(pattern))
paths = sorted(set(paths))
archive = OUT / 'pool-explorer-editable-checkpoint.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for path in paths:
        z.write(path, path.relative_to(ROOT))
    z.writestr('START_HERE.txt', '''ORIGINAL RIGGED POOL EXPLORER - EDITABLE CHECKPOINT

Open tools/blender/avatar/pool_explorer.blend in Blender 4.3.2 or newer.
The AI-generated reference is packed into the .blend and included separately.
The armature has 42 bones and seven original in-place animation actions.

This is an avatar checkpoint, not the complete game. Preserve its folder layout
when merging it into the accompanying Godot project. The PoolAvatar adapter and
tests require the existing PoolPlayer controller. No player physics or collider
is supplied or replaced here.

Rebuild from the project root:
  blender -b --python tools/blender/avatar/build_explorer.py
Verify the saved Blender source:
  blender -b --python tools/blender/avatar/verify_explorer_source.py

Read assets/models/avatar/README.md for integration, layer contracts and limits.
The two included previews are CPU Blender studio renders, not game screenshots.
The final version and earlier native-evidence distinction are recorded in
 tools/blender/avatar/avatar_evidence_versions.json.

Original procedural game character, not a scan or photoreal likeness. No paid,
branded, downloaded character, external rig or motion-capture asset is included.
''')
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
record = {'file': str(archive), 'bytes': archive.stat().st_size,
          'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
          'files': [str(p.relative_to(ROOT)) for p in paths]}
(OUT / 'checkpoint_manifest.json').write_text(json.dumps(record, indent=2))
print(json.dumps(record, indent=2))
