extends RefCounted
## Scene-owned ceramic roughness clones; original G resources are never changed.
## Imported Texture2D resources are shared by this Script, not duplicated per room.
## These three texture references may live for the app lifetime while Catalog keeps
## the builders/this Script loaded. Only scene-owned material clones retire on exit.
## PNG identities/mips are verified offline, never by runtime raw-image reads.
## Call before the existing Clip.install() in each own shell/detail build.
const TILE_ORM:Texture2D=preload("res://assets/dreamcore/uncanny/crossing_inverted_shared/ceramic_gloss/tile_gloss_only_orm.png")
const CYAN_ORM:Texture2D=preload("res://assets/dreamcore/uncanny/crossing_inverted_shared/ceramic_gloss/cyan_gloss_only_orm.png")
const BLUE_ORM:Texture2D=preload("res://assets/dreamcore/uncanny/crossing_inverted_shared/ceramic_gloss/blue_gloss_only_orm.png")
const CROSSING_ACTOR=preload("res://scripts/dreamcore/uncanny/crossing_channels_effects.gd")
const OWNED={"crossing_channels":["crossing_channels_tile","crossing_channels_basin_tile","crossing_channels_cyan","crossing_channels_blue"],"inverted_pool":["inverted_pool_tile","inverted_pool_basin_tile","inverted_pool_pier_tile","inverted_pool_blue","inverted_pool_shell_tile","inverted_pool_shell_floor","inverted_pool_shell_blue"]}
const ORIGINAL_ORM={"tile":"deb590b9d755f0a11b47ce3c8709c87d46ce0dc6aa67664eeb96fcaaa4fb6f90","cyan":"47e810c660beb5bfc2e9b0e1c6be4ff25f0f6931ce609342a67b51e42837c308","blue":"92211e5a726bdd667e23d0c4a28116ed2e75b184fb6373428ca12604f1edbd84"}
const CANDIDATE_ORM={"tile":"aa1df050a7eb6cb67297c3e63d8a809b4fd7c24940e59ae1cf60240a13cdf036","cyan":"ea3e125e40fd22cd00dc14a016c0136a5dcf282b63e00fef6f4e9d0feabe51e0","blue":"e1b55bbb326140090a35cb2ff5d09cccd24a2855bbaf57759a035e21707a4b6c"}
const CLIP_SHADER_SHA="47dd052017699c110bb6907691395f81850e6238a37c8ef3fd71edddbf3c3d1d"
static func texture_for(name:String)->Texture2D:
 match name:
  "tile":return TILE_ORM
  "cyan":return CYAN_ORM
  "blue":return BLUE_ORM
 return null
static func resources()->Dictionary:
 # Fresh small records; immutable texture identities remain shared. No Material cache.
 var out:Dictionary={}
 for name:String in CANDIDATE_ORM:out[name]={"texture":texture_for(name),"sha256":CANDIDATE_ORM[name]}
 return out
static func kind(base:StandardMaterial3D)->String:
 if base==null or base.roughness_texture==null:return ""
 var filename:String=base.roughness_texture.resource_path.get_file()
 for name:String in ORIGINAL_ORM:
  if filename==name+"_orm.png":return name
 return ""
static func original_guard(base:StandardMaterial3D,owner:String)->bool:
 if base==null or not OWNED.has(owner) or base.resource_name not in OWNED[owner]:return false
 var name:String=kind(base)
 if name.is_empty() or not base.roughness_texture.resource_path.begins_with("res://assets/dreamcore/uncanny/"+owner+"/"):return false
 if base.roughness_texture.get_width()!=1024 or base.roughness_texture.get_height()!=1024:return false
 if base.roughness_texture_channel!=BaseMaterial3D.TEXTURE_CHANNEL_GREEN or not base.ao_enabled:return false
 return base.ao_texture==base.roughness_texture and base.ao_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED and base.metallic_texture==null
static func make(base:StandardMaterial3D,owner:String,replacement:Texture2D,expected_sha256:String)->StandardMaterial3D:
 if not original_guard(base,owner) or replacement==null or expected_sha256.is_empty():return null
 if replacement.get_width()!=1024 or replacement.get_height()!=1024:return null
 var name:String=kind(base)
 if expected_sha256!=CANDIDATE_ORM[name] or replacement!=texture_for(name):return null
 # Shallow duplicate preserves all render fields and shared immutable original textures.
 # Only the new ORM resource replaces roughness and its identical-red AO binding.
 var material:StandardMaterial3D=base.duplicate(false) as StandardMaterial3D
 material.roughness_texture=replacement;material.ao_texture=replacement
 var spec:Dictionary=base.get_meta("annex_pbr_spec",{}).duplicate(true)
 if spec.is_empty():return null
 spec.orm=replacement.resource_path;material.set_meta("annex_pbr_spec",spec)
 material.set_meta("ci_gloss_owner",owner);material.set_meta("ci_gloss_original",base)
 material.set_meta("ci_gloss_orm_sha256",expected_sha256)
 return material
static func owned_base(material:Material,owner:String)->StandardMaterial3D:
 var candidate:StandardMaterial3D=material as StandardMaterial3D
 if material is ShaderMaterial:
  if str(material.get_meta("crossing_inverted_clip_owner",""))!=owner or material.shader==null or material.shader.code.sha256_text()!=CLIP_SHADER_SHA:return null
  candidate=material.get_meta("crossing_inverted_clip_base",null) as StandardMaterial3D
 if candidate==null or str(candidate.get_meta("ci_gloss_owner",""))!=owner:return null
 var original:StandardMaterial3D=candidate.get_meta("ci_gloss_original",null) as StandardMaterial3D
 if not original_guard(original,owner):return null
 return candidate
static func install(room:Node3D,owner:String,replacements:Dictionary)->Dictionary:
 return _install_nodes(room.get_children(),owner,replacements)
static func _install_nodes(nodes:Array,owner:String,replacements:Dictionary)->Dictionary:
 # Caller owns only immutable replacement texture records {kind:{texture,sha256}}.
 # Existing clip wrappers are READ ONLY: seed from their owned base metadata,
 # then apply to newly built original Standard meshes before the next clip pass.
 var clones:Dictionary={};var counts={"installed":0,"already_owned":0,"untouched":0,"rejected":0}
 for child:Node in nodes:
  if not child is MeshInstance3D:continue
  var owned:StandardMaterial3D=owned_base(child.material_override,owner)
  if owned!=null:
   var original:StandardMaterial3D=owned.get_meta("ci_gloss_original");clones[original.get_instance_id()]=owned
 for child:Node in nodes:
  if not child is MeshInstance3D:continue
  if owned_base(child.material_override,owner)!=null:counts.already_owned+=1;continue
  var base:StandardMaterial3D=child.material_override as StandardMaterial3D
  if not original_guard(base,owner):counts.untouched+=1;continue
  var name:String=kind(base);var identity:int=base.get_instance_id()
  if not replacements.has(name):counts.rejected+=1;continue
  if not clones.has(identity):
   var record:Dictionary=replacements[name]
   clones[identity]=make(base,owner,record.get("texture") as Texture2D,str(record.get("sha256","")))
  if clones[identity]==null:counts.rejected+=1;continue
  child.material_override=clones[identity];counts.installed+=1
 return counts
static func _actor_meshes(node:Node,out:Array)->void:
 for child:Node in node.get_children():
  if child is MeshInstance3D:out.append(child)
  _actor_meshes(child,out)
static func install_actor(actor:Node3D,replacements:Dictionary)->Dictionary:
 # This exact actor assigns materials only during _ready/_build. Later state,
 # animation and audio methods retain node refs, never replace these materials.
 # Do not broaden this hook to foreign actors or arbitrary horizon descendants.
 if actor==null or actor.get_script()!=CROSSING_ACTOR or not actor.is_node_ready():return {"installed":0,"already_owned":0,"rejected":1}
 var nodes:Array=[];_actor_meshes(actor,nodes)
 var eligible:Array=[];var kinds={"blue":0,"cyan":0}
 for child:MeshInstance3D in nodes:
  var base:StandardMaterial3D=child.material_override as StandardMaterial3D
  var owned:StandardMaterial3D=owned_base(child.material_override,"crossing_channels")
  if owned!=null:base=owned.get_meta("ci_gloss_original") as StandardMaterial3D
  if not original_guard(base,"crossing_channels"):continue
  var name:String=kind(base)
  if not child.mesh is BoxMesh or not kinds.has(name):return {"installed":0,"already_owned":0,"rejected":1}
  kinds[name]+=1;eligible.append(child)
 if eligible.size()!=3 or kinds.blue!=1 or kinds.cyan!=2:return {"installed":0,"already_owned":0,"rejected":1}
 return _install_nodes(eligible,"crossing_channels",replacements)
static func bind_actor_when_ready(actor:Node3D,replacements:Dictionary)->Dictionary:
 if actor==null or actor.get_script()!=CROSSING_ACTOR:return {"installed":0,"already_owned":0,"rejected":1}
 if actor.is_node_ready():return install_actor(actor,replacements)
 # One-shot signal belongs to the actor; free-before-ready releases its bound
 # texture dictionary. Identical repeated binding must not add another callback.
 var callback:Callable=install_actor.bind(actor,replacements)
 if not actor.ready.is_connected(callback):actor.ready.connect(callback,CONNECT_ONE_SHOT)
 return {"installed":0,"already_owned":0,"rejected":0,"pending_ready":true}
static func describe(material:Material,owner:String)->Dictionary:
 var base:StandardMaterial3D=owned_base(material,owner)
 if base==null:return {}
 var original:StandardMaterial3D=base.get_meta("ci_gloss_original")
 return {"owner":owner,"base_key":base.resource_name,"original_orm_path":original.roughness_texture.resource_path,"original_orm_sha256":ORIGINAL_ORM[kind(original)],"hash_authority":"Declared frozen source manifest; imported resource identity, source bytes and complete mips checked by offline native fixture; live maker does no filesystem access","candidate_orm_path":base.roughness_texture.resource_path,"candidate_orm_sha256":base.get_meta("ci_gloss_orm_sha256"),"actual_live_material_spec":base.get_meta("annex_pbr_spec"),"source_cache_untouched":true}
