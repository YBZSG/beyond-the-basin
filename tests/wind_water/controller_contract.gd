extends SceneTree
const Wind=preload('res://scripts/water/wind_wave_controller.gd')
var errors:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:errors.append(label)
func _initialize()->void:
 var w=Wind.new()
 check(is_equal_approx(w.strength,.18),'mild default')
 var initial=w.describe()
 w.set_target({'windStrength':1.0,'windDirection':160.0,'windDensity':2.0})
 check(w.describe().modes==initial.modes,'settings only change targets, no phase reset')
 var previous=w.sample(Vector2(3,-4));var max_delta:=0.0
 for frame in 180:
  w.advance(1.0/60.0,Vector2(3,-4));var next=w.sample(Vector2(3,-4));max_delta=maxf(max_delta,(next-previous).length());previous=next
 check(max_delta<.1,'direction/density/strength bounded smooth step')
 check(w.describe().peak_relief_bound_m<=.006,'6mm relief bound')
 var p:=Vector2(2.18,-5.71);var e:=.0001;var q=w.sample(p)
 var dx:float=(w.sample(p+Vector2(e,0)).x-w.sample(p-Vector2(e,0)).x)/(2*e)
 var dz:float=(w.sample(p+Vector2(0,e)).x-w.sample(p-Vector2(0,e)).x)/(2*e)
 check(absf(dx-q.y)<.0003 and absf(dz-q.z)<.0003,'analytic height derivative')
 check(w.sample(p,0.0,0.0)==Vector3.ZERO,'dry depth mask')
 check(w.sample(p,1.0)==Vector3.ZERO,'subpixel modes band limited')
 var phase=w.phases.duplicate();w.set_target({'windStrength':NAN,'windDirection':INF,'windDensity':'bad','windWaves':false})
 check(w.phases==phase,'toggle preserves phases')
 w.advance(10.0,p)
 check(w.strength==0.0 and w.sample(p)==Vector3.ZERO,'off exact zero after smooth fade')
 check(w.elapsed>12.9,'clock not reset on toggle')
 w.set_target({'windWaves':true,'windStrength':3.0,'windDensity':.01,'windDirection':-90.0})
 check(w.target.windStrength==1.0 and w.target.windDensity==.5 and w.target.windDirection==270.0,'bounded malformed values')
 var slow=Wind.new();var fast=Wind.new()
 for f in 120:slow.advance(1.0/15.0,p)
 for f in 480:fast.advance(1.0/60.0,p)
 var phase_error:=0.0
 for i in 3:phase_error=maxf(phase_error,absf(angle_difference(slow.phases[i],fast.phases[i])))
 check(phase_error<.00001,'constant wind phase independent of 15/60Hz')
 var midpoint=Wind.new();var propagated=Wind.new();var pos:=Vector2(1,2);var m:Vector4=midpoint.modes[0]
 var speed:=midpoint._omega(Vector2(m.x,m.y).length(),midpoint.strength)/Vector2(m.x,m.y).length()
 propagated.advance(.1,pos)
 var along:=Vector2(m.x,m.y).normalized()*speed*.1
 var before_phase:float=Vector2(m.x,m.y).dot(pos)+m.w
 var after_mode:Vector4=propagated.modes[0]
 var after_phase:float=Vector2(after_mode.x,after_mode.y).dot(pos+along)+after_mode.w
 check(absf(angle_difference(before_phase,after_phase))<.00001,'crests travel in positive selected wind direction')
 var states=[]
 for fps in [15,30,60]:
  var c=Wind.new();c.set_target({'windStrength':.8,'windDensity':1.6,'windDirection':150.0})
  for i in fps*4:c.advance(1.0/fps,p)
  states.append(c.describe())
 var morph_phase_error:=0.0
 for i in 3:morph_phase_error=maxf(morph_phase_error,absf(angle_difference(states[0].modes[i].w,states[2].modes[i].w)))
 check(morph_phase_error<.04,'15/60Hz parameter morph phase consistency')
 var seam=Wind.new();seam.set_target({'windDirection':359.0});seam.advance(30.0);var prior:float=seam.direction
 seam.set_target({'windDirection':1.0});seam.advance(1.0/60.0)
 check(angle_difference(prior,seam.direction)>0.0 and absf(angle_difference(prior,seam.direction))<deg_to_rad(.1),'359 to1 shortest positive turn')
 var fresh=Wind.new();fresh.set_target({'windStrength':.73,'windDirection':271.0,'windDensity':1.7});fresh.advance(30.0)
 check(absf(fresh.strength-.73)<.00001 and absf(angle_difference(fresh.direction,deg_to_rad(271.0)))<.00001 and absf(fresh.density-1.7)<.00001,'restored UI targets converge to actual rendering uniforms')
 var shader=load('res://shaders/source_water_surface.gdshader')
 check(shader is Shader,'surface parses with wind include')
 var runtime=load('res://scripts/water/source_water_runtime.gd')
 check(runtime is GDScript and runtime.can_instantiate(),'runtime compile')
 var actual=runtime.new();var solver_before=actual.solver;var phases_before=actual.wind_waves.phases.duplicate();var uniforms_before=actual._surface_uniforms.duplicate()
 actual.set_tuning("windStrength",.73);actual.set_tuning("windDirection",359.0);actual.set_tuning("windDensity",1.7);actual.set_tuning("windWaves",false)
 check(actual.settings.windStrength==.73 and actual.settings.windDirection==359.0 and not actual.settings.windWaves,"runtime wind UI routing")
 check(actual.solver==solver_before and actual.wind_waves.phases==phases_before and actual._surface_uniforms==uniforms_before,"wind edits do not rebind source optical fields or reset phases")
 actual.free()
 print(JSON.stringify({'pass':errors.is_empty(),'checks':checks,'errors':errors,'max_slope_delta_60hz':max_delta,'constant_phase_error_15_60hz':phase_error,'morph_phase_error_15_60hz':morph_phase_error,'scope':'CPU/controller/parser checks only, no native GPU performance claim'}))
 quit(0 if errors.is_empty() else 1)
