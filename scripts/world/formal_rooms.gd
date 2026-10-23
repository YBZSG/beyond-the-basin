class_name FormalPoolRooms
extends RefCounted
## Reconstructed authored wing after workspace replacement. Legacy catalog remains intact.
const COORDS: Array[Vector2i] = [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(0,-2),Vector2i(-1,-2)]
const PATHS := {
 Vector2i(-1,-1): "res://assets/models/formal/formal_mainhall.glb",
 Vector2i(0,-1): "res://assets/models/formal/formal_arcade.glb",
 Vector2i(-1,0): "res://assets/models/formal/formal_sidepool.glb",
 Vector2i(0,-2): "res://assets/models/formal/formal_terrace.glb",
 Vector2i(-1,-2): "res://assets/models/formal/formal_bath.glb"
}
const CONNECTIONS := {
 Vector2i(-1,-1): [Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,-2)],
 Vector2i(0,-1): [Vector2i(-1,-1),Vector2i(0,-2)],
 Vector2i(-1,0): [Vector2i(-1,-1)],
 Vector2i(0,-2): [Vector2i(0,-1),Vector2i(-1,-2)],
 Vector2i(-1,-2): [Vector2i(-1,-1),Vector2i(0,-2)]
}
static func layout(coord: Vector2i, seed_value: int) -> Dictionary:
 var index := COORDS.find(coord)
 assert(index>=0,"Unknown authored room coordinate: "+str(coord))
 var names := ["采光主池厅", "连续拱廊", "静水侧池", "浅水天井", "穹顶静浴"]
 var result := {"coord":coord,"seed":seed_value,"variant":8+index,"formal":true,"daylight":true,"corrupt":0,"tint":0.0,"ducks":0,"name":names[index],"subtitle":"FORMAL POOL WING","water_floor_y":[-0.12,-0.12,-0.52,0.10,-0.62][index],"water_enabled":index!=1,"water_closed_edges":[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN],"fixtures":[],"solids":[],"water_exclusions":[],"water_steps":[],"ceiling":[4.8,4.1,3.9,4.2,5.58][index],"formal_connections":CONNECTIONS[coord].duplicate()}
 result.water_rects = [[Rect2(-8,-6,16,12)],[],[Rect2(-4,-4,8,8)],[Rect2(-6,-4,12,8)],[Rect2(-4.8,-4.8,9.6,10.8)]][index]
 # These finite authored basins cannot use the legacy 32m random prop bounds.
 # Keep every float on water and the dry connecting arcade clear.
 result.prop_spawns=[]
 if index==0:
  result.prop_spawns=[
   {"kind":"duck","position":Vector3(-5.5,.445,-3),"yaw":2.0},
   {"kind":"ball","position":Vector3(5.5,.37,-3),"yaw":.8}]
 elif index==2:
  result.prop_spawns=[
   {"kind":"duck","position":Vector3(1.8,.445,-1.5),"yaw":1.4}]
 elif index==3:
  result.prop_spawns=[
   {"kind":"ball","position":Vector3(3.7,.37,-1.8),"yaw":.7}]
 elif index==4:
  result.prop_spawns=[
   {"kind":"duck","position":Vector3(-2.4,.445,-1.6),"yaw":2.3}]
 result.ducks=result.prop_spawns.size()
 if index==0:
  for i in range(4):
   var top: float=[0.38,0.24,0.10,-0.04][i]
   result.water_steps.append(AABB(Vector3(-2.4,-0.12,5.78-float(i)*0.42-0.21),Vector3(4.8,top+0.12,0.42)))
 if index==2 or index==4:
  # Seven equal risers: six 0.65 m treads, then the continuous basin floor.
  # Wider than the 0.64 m capsule; tread-centre support no longer bridges risers.
  var floor_y:float=-0.52 if index==2 else -0.62
  var width:float=4.8 if index==2 else 3.6
  var entry_z:float=-4.0 if index==2 else 6.0
  var direction_z:float=1.0 if index==2 else -1.0
  var riser:float=(0.52-floor_y)/7.0
  for i in range(6):
   var top:float=0.52-float(i+1)*riser
   var centre_z:float=entry_z+direction_z*(float(i)+0.5)*0.65
   result.water_steps.append(AABB(Vector3(-width/2,floor_y,centre_z-0.325),Vector3(width,top-floor_y,0.65)))
 if index==3:
  for i in range(2):
   var top:float=[0.38,0.24][i]
   result.water_steps.append(AABB(Vector3(-2.0,0.10,3.78-float(i)*0.42-0.21),Vector3(4.0,top-0.10,0.42)))
 result.caustic_reflected_extent = [Vector2(11,10),Vector2(15.7,15.7),Vector2(7,7),Vector2(10,9),Vector2(9.16,9.16)][index]
 result.caustic_transmitted_extent = [Vector2(8,6),Vector2(15.7,15.7),Vector2(4,4),Vector2(6,4),Vector2(4.8,6.0)][index]
 return result
static func spawn(coord: Vector2i) -> Vector3:
 var index := COORDS.find(coord)
 assert(index>=0,"Unknown authored spawn coordinate: "+str(coord))
 var p:Vector3 = [Vector3(0,.55,8),Vector3(-9,.55,0),Vector3(0,.55,5.5),Vector3(0,.55,7),Vector3(0,.55,7.4)][index]
 return p+Vector3(coord.x*32.0,0,coord.y*32.0)
