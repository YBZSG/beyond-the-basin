extends SceneTree
const Wind=preload('res://scripts/water/wind_wave_controller.gd')
func _initialize()->void:
 var w=Wind.new();var material=ShaderMaterial.new();material.shader=load('res://shaders/source_water_surface.gdshader');w.apply_to(material)
 var saved:PackedVector4Array=(material.get_shader_parameter('windModes') as PackedVector4Array).duplicate()
 w.advance(.1,Vector2(3,4))
 var actual:PackedVector4Array=material.get_shader_parameter('windModes')
 var pass_value:bool=actual==saved
 print(JSON.stringify({'pass':pass_value,'saved_uniform_not_mutated_without_rebinding':pass_value,'scope':'Uniform parameter ownership, not proof of GPU race'}))
 quit(0 if pass_value else 1)
