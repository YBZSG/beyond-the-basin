"""No Blender dependency: regression tests for exact positive-area overlap kernel."""
import ast,pathlib,math,json
p=pathlib.Path(__file__).with_name('audit_coplanar.py');tree=ast.parse(p.read_text());ns={};exec(compile(ast.Module(body=[x for x in tree.body if isinstance(x,ast.FunctionDef)and x.name in ('signed','clip')],type_ignores=[]),str(p),'exec'),ns)
area=lambda p:abs(ns['signed'](p));clip=ns['clip'];cases=[]
def check(name,a,b,want):
 got=area(clip(a,b));assert abs(got-want)<1e-9,(name,got,want);cases.append({'name':name,'expected_area':want,'actual_area':got,'pass':True})
square=[(0,0),(1,0),(1,1),(0,1)]
check('identical squares',square,square,1)
check('opposite polygon winding',square,list(reversed(square)),1)
check('edge contact is zero area',square,[(1,0),(2,0),(2,1),(1,1)],0)
check('point contact is zero area',square,[(1,1),(2,1),(2,2),(1,2)],0)
check('partial positive area',square,[(.5,.5),(1.5,.5),(1.5,1.5),(.5,1.5)],.25)
check('triangle partition shared diagonal',[(0,0),(1,0),(0,1)],[(1,0),(1,1),(0,1)],0)
check('thin positive strip',square,[(1-1e-5,0),(2,0),(2,1),(1-1e-5,1)],1e-5)
check('disjoint bounds',square,[(2,2),(3,2),(3,3),(2,3)],0)
root=p.resolve().parents[3];out=root/'output/reference_wing/seam_audit/clipping_regression.json';out.write_text(json.dumps({'pass':True,'cases':cases},indent=2));print('PASS:',len(cases),'polygon-clipping regression cases')
