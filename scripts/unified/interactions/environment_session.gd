extends RefCounted
## Optional unified-map session only. No input, player, persistence or story authority.
signal changed(id: String, value: int)
signal observed(id: String)
signal operated(id: String, value: int)
const VERSION := 1
const MAX_ITEMS := 32
var _items: Dictionary = {}
var _playable := false
var reduced_effects := true
func register_item(id: String, kind: String) -> bool:
 if id.is_empty() or id.length() > 80 or _items.has(id) or _items.size() >= MAX_ITEMS: return false
 if kind not in ["lamp", "presence"]: return false
 _items[id] = {"kind":kind,"value":0,"seen":false,"cooldown":0.0,"look":0.0,"miss":0.0,"away":0.0,"armed":true,"pulse":0.0,"eligible":false}
 return true
func set_playable(value: bool) -> void:
 _playable = value
 if not value:
  for id: String in _items: _items[id].eligible = false
func operate(id: String) -> bool:
 # Host must have already checked range, cone and real line of sight.
 if not _playable or not _items.has(id): return false
 var row: Dictionary = _items[id]
 if row.kind != "lamp" or float(row.cooldown) > 0.0: return false
 row.value = (int(row.value) + 1) % 3
 row.cooldown = 0.8
 changed.emit(id, int(row.value)); operated.emit(id, int(row.value))
 return true
func request_presence_response(id: String) -> bool:
 # Optional host decision, never automatically invoked by every lamp operation.
 if not _playable or reduced_effects or not _items.has(id): return false
 var row: Dictionary = _items[id]
 if row.kind != "presence" or not row.seen or not row.armed or not row.eligible or float(row.cooldown)>0.0: return false
 row.armed = false; row.cooldown = 45.0; row.pulse = 4.0; row.value = 2
 changed.emit(id, 2)
 return true
func advance(delta: float, samples: Dictionary = {}) -> void:
 if not _playable or not is_finite(delta) or delta <= 0.0: return
 var step := minf(delta, 0.25)
 for id: String in _items:
  var row: Dictionary = _items[id]
  row.cooldown = maxf(0.0, float(row.cooldown)-step)
  if row.kind != "presence": continue
  var sample: Dictionary = samples.get(id, {}) if samples.get(id, {}) is Dictionary else {}
  var in_zone: bool = sample.get("in_zone", false) == true
  var eligible: bool = in_zone and sample.get("aligned", false) == true and sample.get("line_clear", false) == true
  row.eligible = eligible
  if not in_zone:
   row.away = minf(8.0, float(row.away)+step)
   if float(row.away) >= 8.0: row.armed = true
  else: row.away = 0.0
  if eligible:
   row.miss = 0.0; row.look = minf(2.0, float(row.look)+step)
   if float(row.look) >= 2.0 and not row.seen:
    row.seen = true; row.value = 1; changed.emit(id,1); observed.emit(id)
  else:
   row.miss = minf(0.5,float(row.miss)+step)
   if float(row.miss) >= 0.5: row.look = 0.0
  if float(row.pulse) > 0.0:
   row.pulse = maxf(0.0,float(row.pulse)-step)
   if float(row.pulse) == 0.0 or reduced_effects:
    row.pulse = 0.0; row.value = 1 if row.seen else 0; changed.emit(id,int(row.value))
func values() -> Dictionary:
 var result: Dictionary = {}
 for id: String in _items: result[id] = int(_items[id].value)
 return result
func observation_values() -> Dictionary:
 var result: Dictionary = {}
 for id: String in _items:
  if _items[id].kind == "presence": result[id] = float(_items[id].look)
 return result
func diagnostics() -> Dictionary:
 return {"playable":_playable,"reduced_effects":reduced_effects,"items":_items.duplicate(true)}
func export_session() -> Dictionary:
 # Caller may keep this in RAM. No filesystem access is performed here.
 var rows: Dictionary = {}
 for id: String in _items:
  var row: Dictionary = _items[id]
  rows[id] = {"kind":row.kind,"value":int(row.value) if row.kind=="lamp" else (1 if row.seen else 0),"seen":bool(row.seen),"cooldown":float(row.cooldown),"armed":bool(row.armed)}
 return {"version":VERSION,"items":rows}
func import_session(data: Dictionary) -> bool:
 # Validate every row before mutation; registered scene identities are authoritative.
 if data.get("version") != VERSION or not data.get("items") is Dictionary: return false
 var rows: Dictionary = data.items
 if rows.size() != _items.size(): return false
 for id: Variant in rows:
  if not id is String or not _items.has(id) or not rows[id] is Dictionary: return false
  var row: Dictionary = rows[id]
  if row.get("kind") != _items[id].kind or not row.get("seen") is bool or not row.get("armed") is bool: return false
  var v: Variant = row.get("value"); var c: Variant = row.get("cooldown")
  if not (v is int or v is float) or not is_finite(float(v)) or float(v)!=floorf(float(v)) or float(v) < 0 or float(v) > (2 if row.kind == "lamp" else 1): return false
  if not (c is int or c is float) or not is_finite(float(c)) or float(c)<0.0 or float(c)>45.0: return false
  if row.kind == "presence" and v != (1 if row.seen else 0): return false
 for id: String in rows:
  var saved: Dictionary = rows[id]; var row: Dictionary = _items[id]
  row.value=int(saved.value);row.seen=saved.seen;row.cooldown=float(saved.cooldown);row.armed=saved.armed
  row.look=0.0;row.miss=0.0;row.away=0.0;row.pulse=0.0;row.eligible=false
 # Restoration is silent. Host applies snapshots before actor activation.
 return true
