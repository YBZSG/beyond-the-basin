extends RefCounted
## EXTERNAL variant5-only layout candidate. No shared player/ladder edits.
## Reuse unchanged original-hall rung/return/flange construction with explicit poses.
const H = preload("res://scripts/world/original_hall_layout.gd")

static func build(b:RefCounted)->void:
 for dx in [-10,10]:
  for dz in [-10,-3,4,11]:
   b.box(dx,4.1,dz,1.5,9.76,1.5,"pale")
   b.box(dx,5.5,dz,4,.3,3,"pale")
 b.box(0,5.5,-12,28,.35,3,"pale")
 # Keep the entire front guard except the single real 1.2m ladder bay.
 b.rail(-14,5.7,-10.6,26.2)
 b.rail(13.4,5.7,-10.6,.6)
 # Inward returns are fully on the gallery slab, never floating out over water.
 b.rail(12.2,5.7,-11.2,.6,false)
 b.rail(13.4,5.7,-11.2,.6,false)
 _access(b,"GalleryEastAccess",Vector3(12.8,-.70,-8.9),Vector3(12.8,5.695,-10.2),Vector3(12.8,5.695,-11.05),-10.5)
 _tower(b)
 b.sign_board(8,3,-15.65,b.decay_text("午后\n无人"))

static func _tower(b:RefCounted)->void:
 # Centre lies between the unchanged z=-3 and z=4 hall columns.
 # Retain the original stem and upper slab proportions; only the lower
 # receiving platform is lengthened southward for a supported second flight.
 b.box(-10,2.06,0,.85,5.68,1.1,"pale")
 b.box(-10.6,2.5,.75,2.8,.22,3.9,"pale")
 b.box(-10.6,5.0,0,2.8,.22,2.4,"pale")
 # The enlarged lower landing has its own connected beam and two floor feet.
 b.box(-10.6,2.29,2.2,2.8,.202,.3,"pale")
 for x in [-11.65,-9.55]:
  b.box(x,.735,2.2,.22,2.91,.22,"pale")
 # Lower guard: one 1.2m controlled entry at the front-left, no railing
 # across the actual transfer path to the upper-flight base.
 b.rail(-11.9,2.61,-1.1,2.6)
 b.rail(-11.9,2.61,-1.1,3.7,false)
 b.rail(-9.3,2.61,-1.1,3.7,false)
 b.rail(-10.7,2.61,2.6,1.4)
 # Upper platform remains enclosed except the corresponding 1.2m bay.
 b.rail(-11.9,5.11,-1.1,2.6)
 b.rail(-11.9,5.11,-1.1,2.2,false)
 b.rail(-9.3,5.11,-1.1,2.2,false)
 b.rail(-11.9,5.11,1.1,.4)
 b.rail(-10.3,5.11,1.1,1.)
 b.rail(-11.5,5.11,.5,.6,false)
 b.rail(-10.3,5.11,.5,.6,false)
 _access(b,"TowerLowerAccess",Vector3(-11.3,-.70,4.2),Vector3(-11.3,2.63,3.0),Vector3(-11.3,2.63,2.2),2.7)
 _access(b,"TowerUpperAccess",Vector3(-10.9,2.63,1.9),Vector3(-10.9,5.13,1.5),Vector3(-10.9,5.13,.7),1.2)
 b.sign_board(-10.65,3.6,.57,"禁止\n跳水")

static func _access(b:RefCounted,label:String,base:Vector3,top:Vector3,finish:Vector3,edge:float)->void:
 H._ladder(b,label,base,top,finish)
 var anchor:Node3D=b.room.get_node(NodePath(label))
 var construction:Dictionary=anchor.get_meta("construction")
 # H's generic annotation assumes its old .18m layout. Bind this new layout
 # to its true edge instead, without changing any rung or grip formula.
 construction.receiving_edge_gap_from_top=absf(top.z-edge)
 construction.receiving_edge_z=edge
 construction.layout_scope="external_variant5_only"
 anchor.set_meta("construction",construction)
