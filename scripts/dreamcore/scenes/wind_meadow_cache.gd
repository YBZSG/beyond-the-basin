extends RefCounted
## Bounded, data-only procedural recipe cache. No Variant object deserialization.
## Runtime trusts only exact bytes listed in the shipped finite-validated manifest.
const ROOT:="res://assets/dreamcore/outdoor/grass_recipes"
const SCHEMA:=1
const SEED_VERSION:=1
const GENERATOR_VERSION:=1
const MAGIC:="PCGRASS1"
const HEADER_BYTES:=140
const MAX_FILE_BYTES:=3500000
const MAX_RAW_BYTES:=3300000
const MAX_INSTANCES:=50000
static var manifest:Dictionary={}
static var manifest_loaded:=false
static func digest(bytes:PackedByteArray)->PackedByteArray:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():h.update(bytes)
	return h.finish()
static func key(style:String,coord:Vector2i)->String:
	return "%s/cell_%d_%d.grassbin"%[style,coord.x,coord.y]
static func signature(config:Dictionary,layers:Array)->String:
	var clean:=config.duplicate(true)
	for field in ["audit","stream_radius","recipe_mode"]:clean.erase(field)
	var shapes:Array=[]
	for layer:Dictionary in layers:shapes.append([layer.density,layer.leaves])
	return digest(var_to_bytes([SCHEMA,SEED_VERSION,GENERATOR_VERSION,12347,8.0,.24,141.6,shapes,clean])).hex_encode()
static func load_manifest()->Dictionary:
	if manifest_loaded:return manifest
	manifest_loaded=true
	var f:=FileAccess.open(ROOT+"/manifest.json",FileAccess.READ)
	if f==null or f.get_length()>1000000:return {}
	var parsed:Variant=JSON.parse_string(f.get_as_text());f.close()
	if not parsed is Dictionary:return {}
	if parsed.get("schema",0)!=SCHEMA or parsed.get("finite_validator_version",0)!=1:return {}
	if not parsed.get("entries",null) is Dictionary or parsed.entries.size()!=243:return {}
	manifest=parsed;return manifest
static func reload_manifest()->void:
	manifest.clear();manifest_loaded=false
static func decode_buffer(buffer:PackedFloat32Array)->Dictionary:
	var transforms:Array[Transform3D]=[];var custom:Array[Color]=[]
	for o in range(0,buffer.size(),16):
		transforms.append(Transform3D(Basis(Vector3(buffer[o],buffer[o+4],buffer[o+8]),Vector3(buffer[o+1],buffer[o+5],buffer[o+9]),Vector3(buffer[o+2],buffer[o+6],buffer[o+10])),Vector3(buffer[o+3],buffer[o+7],buffer[o+11])))
		custom.append(Color(buffer[o+12],buffer[o+13],buffer[o+14],buffer[o+15]))
	return {"transforms":transforms,"custom":custom}
static func pack_buffer(transforms:Array,custom:Array)->PackedFloat32Array:
	var data:=PackedFloat32Array()
	for i in range(transforms.size()):
		var t:Transform3D=transforms[i];var c:Color=custom[i]
		data.append_array(PackedFloat32Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z,c.r,c.g,c.b,c.a]))
	return data
static func read_recipe(style:String,coord:Vector2i,expected_config:String,strict_finite:bool=false)->Dictionary:
	if not style in ["sports","courtyard","verge"] or absi(coord.x)>4 or absi(coord.y)>4:return {"error":"invalid_request"}
	var m:=load_manifest();var name:=key(style,coord)
	if not m.has("entries") or not m.entries.has(name):return {"error":"manifest_missing"}
	var entry:Variant=m.entries[name]
	if not entry is Dictionary or entry.get("finite_validated",false)!=true:return {"error":"manifest_not_finite_validated"}
	if entry.get("config_sha256","")!=expected_config:return {"error":"stale_config"}
	var f:=FileAccess.open(ROOT+"/"+name,FileAccess.READ)
	if f==null:return {"error":"missing_file"}
	var size:=f.get_length()
	if size<HEADER_BYTES or size>MAX_FILE_BYTES or size!=entry.get("file_bytes",-1):f.close();return {"error":"file_size"}
	var bytes:=f.get_buffer(size);f.close()
	return decode_recipe(bytes,entry,coord,expected_config,strict_finite)
static func decode_recipe(bytes:PackedByteArray,entry:Dictionary,coord:Vector2i,expected_config:String,strict_finite:bool=false)->Dictionary:
	var size:=bytes.size()
	if size<HEADER_BYTES or size>MAX_FILE_BYTES or size!=entry.get("file_bytes",-1):return {"error":"file_size"}
	# This external packaged manifest, not a self-declared hash inside the blob,
	# binds the runtime fast path to author-validated finite IEEE754 data.
	if digest(bytes).hex_encode()!=entry.get("file_sha256",""):return {"error":"file_integrity"}
	var s:=StreamPeerBuffer.new();s.data_array=bytes;s.big_endian=false
	if s.get_data(8)[1].get_string_from_ascii()!=MAGIC:return {"error":"magic"}
	if s.get_u32()!=SCHEMA or s.get_u32()!=SEED_VERSION or s.get_u32()!=GENERATOR_VERSION:return {"error":"schema_or_seed_version"}
	if s.get_32()!=coord.x or s.get_32()!=coord.y:return {"error":"coordinate"}
	var batches:=s.get_u32();var instances:=s.get_u32();var raw_size:=s.get_u32();var packed_size:=s.get_u32()
	if batches>48 or instances>MAX_INSTANCES or raw_size>MAX_RAW_BYTES or raw_size!=batches*16+instances*64:return {"error":"bounded_counts"}
	if instances!=entry.get("instances",-1) or batches!=entry.get("batches",-1):return {"error":"manifest_counts"}
	if packed_size!=size-HEADER_BYTES:return {"error":"packed_size"}
	if s.get_data(32)[1].hex_encode()!=expected_config:return {"error":"header_config"}
	var raw_hash:PackedByteArray=s.get_data(32)[1];var packed_hash:PackedByteArray=s.get_data(32)[1]
	var packed:PackedByteArray=s.get_data(packed_size)[1]
	# Normal loads already verified the entire header+compressed payload against
	# the external manifest. Rehash nested payloads only in exhaustive QA.
	if strict_finite and digest(packed)!=packed_hash:return {"error":"compressed_integrity"}
	var raw:=packed.decompress(raw_size,FileAccess.COMPRESSION_ZSTD) if raw_size>0 else PackedByteArray()
	if raw.size()!=raw_size or raw_hash.hex_encode()!=entry.get("raw_sha256",""):return {"error":"decoded_integrity"}
	if strict_finite and digest(raw)!=raw_hash:return {"error":"decoded_integrity"}
	var payload:=StreamPeerBuffer.new();payload.data_array=raw;payload.big_endian=false
	var records:Array=[];var found_instances:=0;var sites:Dictionary={}
	for _i in range(batches):
		if payload.get_available_bytes()<16:return {"error":"short_record"}
		var layer:=payload.get_u32();var ix:=payload.get_u32();var iz:=payload.get_u32();var count:=payload.get_u32()
		if layer>2 or ix>3 or iz>3 or count==0 or count>2048 or payload.get_available_bytes()<count*64:return {"error":"record_bounds"}
		var site:=Vector3i(ix,iz,layer)
		if sites.has(site):return {"error":"duplicate_batch"}
		sites[site]=true
		var buffer:PackedFloat32Array=payload.get_data(count*64)[1].to_float32_array()
		if strict_finite:
			for value:float in buffer:
				if not is_finite(value):return {"error":"nonfinite"}
		found_instances+=count
		records.append({"layer":layer,"ix":ix,"iz":iz,"count":count,"buffer":buffer})
	if payload.get_available_bytes()!=0 or found_instances!=instances:return {"error":"trailing_or_count_mismatch"}
	return {"records":records,"instances":instances,"file_bytes":size,"raw_bytes":raw_size,"finite_validation":"strict_scan" if strict_finite else "exact_packaged_manifest_identity"}
static func write_recipe(path:String,coord:Vector2i,config_hash:String,records:Array)->Dictionary:
	var payload:=StreamPeerBuffer.new();payload.big_endian=false;var instances:=0
	for entry:Dictionary in records:
		var data:PackedFloat32Array=entry.buffer
		assert(data.size()==entry.count*16 and entry.count<=2048)
		for value:float in data:assert(is_finite(value),"Never cache NaN or infinity")
		payload.put_u32(entry.layer);payload.put_u32(entry.ix);payload.put_u32(entry.iz);payload.put_u32(entry.count);payload.put_data(data.to_byte_array());instances+=entry.count
	var raw:=payload.data_array;assert(raw.size()<=MAX_RAW_BYTES and instances<=MAX_INSTANCES and records.size()<=48)
	var packed:=raw.compress(FileAccess.COMPRESSION_ZSTD) if not raw.is_empty() else PackedByteArray()
	var out:=StreamPeerBuffer.new();out.big_endian=false;out.put_data(MAGIC.to_ascii_buffer());out.put_u32(SCHEMA);out.put_u32(SEED_VERSION);out.put_u32(GENERATOR_VERSION);out.put_32(coord.x);out.put_32(coord.y);out.put_u32(records.size());out.put_u32(instances);out.put_u32(raw.size());out.put_u32(packed.size());out.put_data(config_hash.hex_decode());out.put_data(digest(raw));out.put_data(digest(packed));assert(out.get_position()==HEADER_BYTES);out.put_data(packed)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir());var f:=FileAccess.open(path,FileAccess.WRITE);assert(f!=null);f.store_buffer(out.data_array);f.close()
	return {"schema":SCHEMA,"seed_version":SEED_VERSION,"generator_version":GENERATOR_VERSION,"config_sha256":config_hash,"instances":instances,"batches":records.size(),"raw_bytes":raw.size(),"file_bytes":out.data_array.size(),"raw_sha256":digest(raw).hex_encode(),"file_sha256":digest(out.data_array).hex_encode(),"finite_validated":true}
