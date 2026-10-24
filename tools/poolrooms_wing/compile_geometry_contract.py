"""Compile audited assembly metadata into export-safe GDScript constants."""
from pathlib import Path
import json, hashlib
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'source_provenance/poolrooms_wing/geometry.json'
data=json.loads(source.read_text())
def number(v):return format(float(v),'.9g')
def vec(v):return 'Vector3('+','.join(map(number,v))+')'
lines=['extends RefCounted','## Generated from the assembled geometry contract; run compile_geometry_contract.py after geometry changes.','const SOURCE_SHA256 := '+json.dumps(hashlib.sha256(source.read_bytes()).hexdigest()),'const ROOMS := [']
for name in ['crescent_court','vaulted_lanes','circular_bath']:
 r=data['rooms'][name];lines+=[' {','  "ceiling":'+number(r['ceiling'])+',','  "interior_ceiling":'+number(r['interior_ceiling'])+',','  "spawn_local":'+vec(r['spawn_local'])+',','  "water_steps":[']
 for b in r['water_steps']:lines+=['   AABB('+vec(b['position'])+','+vec(b['size'])+'),']
 lines+=['  ],','  "fixtures":[']
 for f in r['fixtures']:lines+=['   {"geometry":"authored_wall","position":'+vec(f['position'])+',"color":Color('+json.dumps(f['color'])+'),"power":'+number(f['power'])+',"range":'+number(f.get('range',12.0))+',"alive":true,"flicker":false,"power_scale":1.0},']
 lines+=['  ],',' },']
lines+= [']','']
(ROOT/'scripts/poolrooms_wing/geometry_contract.gd').write_text('\n'.join(lines))
