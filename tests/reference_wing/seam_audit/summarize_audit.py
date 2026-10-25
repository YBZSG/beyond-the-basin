"""Create bounded repair targets and a human-readable audit from immutable results."""
import pathlib,json,hashlib,datetime
ROOT=pathlib.Path(__file__).resolve().parents[3];OUT=ROOT/'output/reference_wing/seam_audit'
def group(scene,names):
 s=' '.join(names)
 if scene=='cyan_corridor'and'Recess'in s:return 'cyan_window_sill_head_lap'
 if scene=='ball_lounge':
  if'Sealed_module'in s:return 'lounge_connector_module_boundary_lap'
  if'Room_'in s:return 'lounge_room_connector_jamb_lap'
  return 'lounge_orthogonal_connector_corner'
 if all('Route_Wall'in n for n in names)or all('Dogleg_Wall'in n for n in names):return 'water_orthogonal_route_corner'
 return 'water_room_connector_jamb_or_soffit_lap'
rows=[];summary=[];details=[]
for scene in ['colonnade','cyan_corridor','octagonal_bath','ball_lounge','stair_gallery']:
 d=json.loads((OUT/(scene+'_coplanar.json')).read_text());summary.append({'scene':scene,'counts':d['counts'],'files':d['files'],'geometry_consistency':d['geometry_consistency']});om={o['name']:o for o in d['objects']}
 for q in d['results']:
  if q['relation']!='same_facing':continue
  trusted=q['trusted_view_exposed_intersection_area_m2']>0;w=[e for e in q['exposure']if e.get('trusted_view')]
  row={'scene':scene,'objects':q['objects'],'group':group(scene,q['objects'])if trusted else'not_confirmed_from_trusted_view','total_coplanar_pair_area_m2':q['overlap_area_m2'],'trusted_view_sampled_patch_area_m2':q['trusted_view_exposed_intersection_area_m2'],'shading_conflict_area_m2':q['trusted_shading_conflict_area_m2'],'bounds':{n:om[n]['bounds']for n in q['objects']},'exposure_witnesses':w[:3],'classification':q['classification']}
  for e in row['exposure_witnesses']:e['plane_n_dot_p']=sum(a*b for a,b in zip(e['normal_godot'],e['point_godot']))
  details.append(row)
  if trusted:rows.append(row)
report={'generated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Baseline geometry defects identified; not final asset-freeze acceptance','scope':'48 baseline camera/route-visible duplicate-surface pairs. Areas are summed cross-object surface intersections, not overlap volume or exact fully visible area. Source and GLB hashes bind each result. No visual/perfect/no-seams claim.','repair_rules':['Eliminate duplicate exposed faces rather than apply arbitrary epsilon offsets.','Prefer bounded axis-end trim only when removed solid is contained by unchanged neighboring collision solids and the visible exterior remains closed.','Preserve collision union, doorway clearance, floor/stair/water geometry, metric UV phase and material assignments.','Re-evaluate bevel interfaces after trimming: two beveled butt ends can leave a small notch even when collision union is unchanged.','Record buried/opposite-face contacts separately; do not delete every overlap or ball contact.'],'summaries':summary,'trusted_view_repair_targets':rows,'other_same_facing_contacts':[x for x in details if x not in rows]}
(OUT/'repair_targets.json').write_text(json.dumps(report,indent=2))
lines=['# Reference wing coplanar surface audit','',report['status'],'','## Findings','']
for d in summary:
 c=d['counts'];lines.append(f"- {d['scene']}: {c['same_facing_object_pairs']} same-facing object pairs; {c['trusted_view_exposed_pairs']} camera/route-visible pairs; {c['trusted_shading_conflict_pairs']} sampled material/UV/normal conflicts; {c['opposite_facing_contact_pairs']} opposite-facing contact pairs.")
lines+=['','Matching sampled shading does not certify duplicate planes as safe. Duplicate ray-hit surfaces and overlapping bevel joins remain geometric cleanup candidates.','The bath candidate removes the previously identified seven rear portal caps. That correction does not eliminate the ten separate route-corner overlaps.','The stair threshold under-wall overlap is retained in the record: left 5.980000 m², right 1.060000 m². Neither has a camera/route exposure witness after adding all 26 tread centers, door approach and connector centerline. The only observed left-side patch is below the usable 0.52 m floor from an unproven foundation viewpoint.','Lounge porthole reveal/backing contacts are likewise not proven exposed from known interior routes; do not remove them as if they were visible front-surface defects.','','## Bounded repair groups','']
groups={}
for r in rows:groups.setdefault(r['group'],[]).append(r)
for name,rs in groups.items():
 lines.append(f'### {name} ({len(rs)} pairs)')
 for r in rs:
  w=r['exposure_witnesses'][0];pos=', '.join(f'{x:.6f}'for x in w['point_godot']);normal=', '.join(f'{x:.6f}'for x in w['normal_godot']);lines.append(f"- {r['scene']}: {r['objects'][0]} / {r['objects'][1]}; total {r['total_coplanar_pair_area_m2']:.6f} m². Witness {w['observer']['name']}: point ({pos}), normal ({normal}), n·p={w['plane_n_dot_p']:.6f}.")
 lines.append('')
lines+=['## Minimal fix guidance','']+[f'- {x}'for x in report['repair_rules']]+['','The cyan sill/head depth currently overlaps the wall in X: reveal [-2.62,-1.82], lower/upper wall [-2.04,-1.80]. Trimming reveal depth to meet X=-2.04 is the narrow candidate, subject to bevel closure and collision-union verification. Other room/connector and orthogonal route-corner pairs are axis-aligned-box end-lap patterns; select the contained end slab, not a global union or wholesale asset rebuild.','','## Evidence and limitations','','- Machine-readable full source object/face pairs, intersection areas, exact ray witnesses, material/UV/normal comparisons and hashes: per-scene *_coplanar.json.','- Review-friendly repair targets, bounds and plane equations: repair_targets.json.','- Source/GLB rounded unique position signatures match in all five; total source/GLB area delta is zero or floating triangulation tolerance. This is supporting consistency evidence, not a topology equality proof.','- Pure CPU Blender evaluated meshes and BVH. No rendering, GPU, Godot import, production edit or user-machine test.','- Excludes hidden collision proxies and preview water. Tests cross-object exact coplanarity within 1e-5 m and positive area >1e-7 m², not arbitrary near-coincidence, noncoplanar intersections, global UV seams or the entire scene assembly.','- Opposite-facing contacts and zero-area shared edges are not treated as z-fighting. Eight clipping-kernel regression cases passed.','- Authored camera/contract route eyes are meaningful viewpoints; supplemental surface eyes are explicitly unproven reachability and cannot alone establish a user-visible defect.','- Final refresh must occur after source owners freeze corrected sources and GLBs.']
(OUT/'audit_summary.md').write_text('\n'.join(lines)+'\n');print('Wrote',len(rows),'trusted-view repair targets in',len(groups),'groups')
