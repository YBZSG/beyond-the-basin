"""Final room-local practical recipes, no QA/candidate input dependency.
Invoked by the production generator only after the authored candidates are accepted.
"""
import bpy,math
from mathutils import Vector

def apply_final_lighting(G,OB,M,runtime,preview,box,light,bbox):
 def p(v):return(v[0],-v[2],v[1])
 def row(name):return next(r for r in G['lights']if r['name']==name)
 def mount(name,support,axis,side,supportside):
  a,b=bbox(OB[name]),bbox(OB[support]);gap=a[side][axis]-b[supportside][axis];assert abs(gap)<1e-5
  return{'fixture':name,'support_object':support,'mount_axis':'XYZ'[axis],'fixture_mount_coordinate':round(a[side][axis],6),'support_coordinate':round(b[supportside][axis],6),'mount_gap':round(gap,6),'measured_from':'actual authored mesh vertices'}
 if G['name']=='cyan_corridor':
  for old,new in[('ref_tile_teal_satin','ref_tile_cyan_satin'),('ref_tile_teal_satin_dry','ref_tile_cyan_satin_dry')]:
   m=M[old].copy();m.name=new;M[new]=m
   for ob in runtime.objects:
    for i,mat in enumerate(ob.data.materials):
     if mat==M[old]:ob.data.materials[i]=m
  G['material_contract'].update(structure='ref_tile_cyan_satin',dry_surfaces='ref_tile_cyan_satin_dry',face_srgb='#63B0A6',grout_srgb='#4D8279',scope='Reference2-only saturated green-cyan satin; existing colonnade teal unchanged. Palette inferred from uncalibrated reference, not measured physical albedo.')
  G['fixture_mounts']=[]
  for i,(z,energy,support)in enumerate([(9.8,.90,'Left_FinalBay'),(7.7,.80,'Window_4_UpperWall'),(2.9,.65,'Window_3_UpperWall'),(-2.6,.45,'Window_2_UpperWall'),(-7.4,.18,'Window_1_UpperWall'),(-10.7,.06,'Left_SolidBay_00')]):
   name=f'CyanStrip_{i+1:02d}'
   for suffix in['_MetalHousing','_Diffuser']:
    bpy.data.objects.remove(OB[name+suffix],do_unlink=True);del OB[name+suffix]
   box(name+'_MetalHousing',[-1.7725,2.925,z],[.055,.70,.085],'ref_fixture_metal',False,.003);box(name+'_Diffuser',[-1.7385,2.925,z],[.013,.65,.045],'ref_fixture_emission',False,.001)
   r=row(name);r.update(position=[-1.72,2.925,z],color=[.72,1,1],energy=energy,source_watts=energy*100,range=6,native_type='spot',direction=[1,0,0],emission_direction=[1,0,0],spot_angle_deg=85,spot_angle_attenuation=.15,emitter_radius=.005,color_space='linear',fixture_object=name+'_Diffuser',preview_emitter_shape='RECTANGLE',preview_emitter_size_m=[.035,.65])
   ob=bpy.data.objects['PREVIEW_'+name];ob.location=p(r['position']);ob.rotation_euler=Vector(p(r['direction'])).to_track_quat('-Z','Y').to_euler();ob.data.energy=energy*100;ob.data.color=r['color'];ob.data.shape='RECTANGLE';ob.data.size=.035;ob.data.size_y=.65
   G['fixture_mounts'].append(mount(name+'_MetalHousing',support,0,0,1))
  G['composition']['intent']='Narrow cyan tiled tube, true black recessed windows with slim jambs, six supported upper-left vertical practicals, anchored no-entry sign and dark far end. High bars are a plausible architectural reading of the reference.'
 elif G['name']=='octagonal_bath':
  dim=M['ref_fixture_emission'].copy();dim.name='ref_bath_cove_dim_emission';dim.node_tree.nodes.get('Principled BSDF').inputs['Emission Strength'].default_value=.15;M[dim.name]=dim
  for ob in runtime.objects:
   if ob.name.startswith('Bath_CoveDiffuser_'):ob.data.materials[0]=dim
  for r in G['lights']:
   if r['name'].startswith('Bath_CoveSample_'):r['runtime_enabled']=False;bpy.data.objects['PREVIEW_'+r['name']].hide_render=True
   if r['name']in['Bath_WestConnectorFixture','Bath_SouthConnectorFixture']:r['shadow']=False
  r=row('Bath_LeftPortalHiddenLamp');direction=list((Vector([-1.45,.52,-4.5])-Vector(r['position'])).normalized());r.update(energy=1.2,source_watts=120,color=[1,.58,.28],color_space='linear',native_type='spot',direction=direction,emission_direction=direction,spot_angle_deg=75,spot_angle_attenuation=.35,emitter_radius=.005,preview_emitter_shape='POINT_SPOT',position_note='Existing ceiling-supported practical inside left connector, hidden above doorway lintel, aimed outward/down through real opening.')
  ob=bpy.data.objects['PREVIEW_'+r['name']];ob.data.type='SPOT';ob.data.energy=120;ob.data.color=r['color'];ob.data.shadow_soft_size=.005;ob.data.spot_size=math.radians(150);ob.data.spot_blend=.35;ob.rotation_euler=Vector(p(direction)).to_track_quat('-Z','Y').to_euler()
  amber=M['ref_fixture_emission'].copy();amber.name='ref_fixture_amber_emission';bs=amber.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(1,.58,.28,1);bs.inputs['Emission Color'].default_value=(1,.58,.28,1);M[amber.name]=amber;OB['Bath_LeftPortalHiddenLamp_Diffuser'].data.materials[0]=amber
  G['fixture_mounts'].append(mount('Bath_LeftPortalHiddenLamp_MetalHousing','Bath_WestRoute_Roof_014',1,1,0))
  name='Bath_EntrySidePractical';box(name+'_MetalHousing',[0,3.05,6.46],[.90,.18,.08],'ref_fixture_metal',False,.003);box(name+'_Diffuser',[0,3.05,6.414],[.82,.12,.012],'ref_fixture_emission',False,.001);ob=light(name,[0,3.05,6.385],[.82,.90,1],800,16,.82);direction=[0,.1,-1];ob.rotation_euler=Vector(p(direction)).to_track_quat('-Z','Y').to_euler();ob.data.shape='RECTANGLE';ob.data.size=.82;ob.data.size_y=.12
  row(name).update(direction=direction,emission_direction=direction,fixture_object=name+'_Diffuser',preview_emitter_shape='RECTANGLE',preview_emitter_size_m=[.82,.12]);G['fixture_mounts'].append(mount(name+'_MetalHousing','Octagonal_WallFacet_05',2,1,0))
  G['composition']['intent']='Human-scale blush octagonal stepped bath, real amber-lit left connector cavity, dark right portal, complete concentric coffer. No exterior washer, bright cove ring or floating fill.'
