import bpy,sys,os,json,argparse
p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--output',required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);bpy.ops.wm.open_mainfile(filepath=a.input)
o=bpy.data.objects['CenjiCircularGateway'];uv=o.data.uv_layers.active;rows=[]
for f in o.data.polygons:
 for k,li in enumerate(f.loop_indices):
  lj=f.loop_indices[(k+1)%len(f.loop_indices)];v1=o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co;v2=o.matrix_world@o.data.vertices[o.data.loops[lj].vertex_index].co;dd=(v2-v1).length
  if dd<=1e-6:continue
  du=(uv.data[lj].uv-uv.data[li].uv).length;rows.append({'polygon':f.index,'edge_m':dd,'uv_edge_units':du,'ratio':du/dd,'absolute_metric_error_m':abs(dd-du)})
rows.sort(key=lambda x:abs(x['ratio']-1),reverse=True);r={'object':o.name,'worst_edges':rows[:12],'max_absolute_metric_error_m':max(x['absolute_metric_error_m'] for x in rows),'ratio_range_for_edges_at_least_1cm':[min(x['ratio'] for x in rows if x['edge_m']>=.01),max(x['ratio'] for x in rows if x['edge_m']>=.01)]};json.dump(r,open(a.output,'w'),indent=2);print(json.dumps(r,indent=2))
