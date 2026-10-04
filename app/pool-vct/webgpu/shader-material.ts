import * as T from 'three';
import * as TSL from 'three/tsl';
import { NodeMaterial, type NodeBuilder, type WebGPURenderer } from 'three/webgpu';
import Transpiler from 'three/addons/transpiler/Transpiler.js';
import GLSLDecoder from 'three/addons/transpiler/GLSLDecoder.js';
import TSLEncoder from 'three/addons/transpiler/TSLEncoder.js';
import { waterVisibility } from './bvh-visibility.ts';
import { extendSceneMaterial } from './materials.ts';
import { legacyTexture } from './legacy-texture.ts';

// Preserve the existing numerical shaders while compiling their expressions
// to native TSL/WGSL. No WebGL context or cross-device texture copies are used.
// The transpiler only consumes the shaders shipped with this application.
export function installShaderMaterials(renderer: WebGPURenderer) {
  // The liquid pass can be compiled before the first room probe is ready.
  // Its fallback has the same CubeUV layout as the 256px probe's PMREM.
  const emptyEnvironment=new T.DataTexture(new Uint8Array(768*1024*4),768,1024);
  emptyEnvironment.mapping=T.CubeUVReflectionMapping;
  emptyEnvironment.name='pool-empty-environment';emptyEnvironment.needsUpdate=true;
  const dispose=renderer.dispose.bind(renderer);
  renderer.dispose=()=>{emptyEnvironment.dispose();dispose();};
  const nodes=(renderer as unknown as {_nodes:{getForRenderCacheKey(object:{material:T.Material}):unknown}})._nodes;
  const cacheKey=nodes.getForRenderCacheKey.bind(nodes);
  nodes.getForRenderCacheKey=object=>object.material instanceof T.ShaderMaterial||Object.keys(object.material.userData).some(key=>key.startsWith('pool'))
    ? `${cacheKey(object)}:${object.material.uuid}` : cacheKey(object);
  const library = renderer.library as unknown as { fromMaterial(material: T.Material): NodeMaterial | null };
  const original = library.fromMaterial.bind(library);
  library.fromMaterial = (material: T.Material) => {
    if (!(material instanceof T.ShaderMaterial)) {
      const node=original(material);return node?extendSceneMaterial(node,material):null;
    }
    const node = new NodeMaterial();
    for (const key of ['side','transparent','opacity','blending','blendSrc','blendDst','blendEquation','depthTest','depthWrite','depthFunc','colorWrite','toneMapped','fog','polygonOffset','polygonOffsetFactor','polygonOffsetUnits'] as const) {
      Object.assign(node, { [key]: material[key] });
    }
    const varyings = new Map<string, unknown>();
    const builtins: Record<string, unknown> = {
      nodeFloat: TSL.float,
      poolDiscard: TSL.Discard,
      position: TSL.positionGeometry, normal: TSL.normalGeometry, uv: TSL.uv(),
      modelMatrix: TSL.modelWorldMatrix, modelViewMatrix: TSL.modelViewMatrix,
      projectionMatrix: TSL.cameraProjectionMatrix, viewMatrix: TSL.cameraViewMatrix,
      normalMatrix: TSL.modelNormalMatrix, cameraPosition: TSL.cameraPosition,
      pixelCoord: TSL.vec4(renderer.coordinateSystem===T.WebGPUCoordinateSystem
        ? TSL.vec2(TSL.screenCoordinate.x,TSL.screenSize.y.sub(TSL.screenCoordinate.y)) : TSL.screenCoordinate, 0, 1),
      instanceMatrix: TSL.Fn((_: unknown, builder: NodeBuilder) => TSL.instancedBufferAttribute((builder.object as T.InstancedMesh).instanceMatrix, 'mat4'))(),
    };
    if(material.uniforms.environment){
      builtins.textureCubeUV=(_:unknown,direction:never,roughness:never)=>{
        const entry=material.uniforms.environment;
        const map=TSL.pmremTexture(entry.value??emptyEnvironment,direction,roughness);
        const update=map.updateBefore.bind(map);
        map.updateBefore=frame=>{
          const value=entry.value??emptyEnvironment;
          if(map.value!==value)map.value=value;
          return update(frame);
        };
        return TSL.vec4(map,1);
      };
    }
    if(material.uniforms.rtBvh)builtins.waterRayVisible=waterVisibility(material.uniforms);
    const tsl = { ...TSL,
      vec3: (...args: unknown[]) => args.length===1&&typeof args[0]==='object'?TSL.convert(args[0] as never,'vec3'):TSL.vec3(...args as Parameters<typeof TSL.vec3>),
      vec2: (...args: unknown[]) => args.length===1&&typeof args[0]==='object'?TSL.convert(args[0] as never,'vec2'):TSL.vec2(...args as Parameters<typeof TSL.vec2>),
      reference: (property: string, type: never, object: T.IUniform) => {
      if (type === 'texture') {
        return legacyTexture(object);
      }
      if(Array.isArray(object.value))return TSL.uniformArray(object.value,type);
      if(object.value instanceof T.Color)return TSL.reference(property,'color',object);
      return TSL.reference(property, type, object);
    }, varying: (value: never, name: string) => {
      if (!varyings.has(name)) varyings.set(name, TSL.varying(value, name));
      return varyings.get(name);
    } };
    const compile = (source: string, vertex: boolean) => {
      if(source.includes('uniform BVH rtBvh'))source=source.slice(source.indexOf('uniform sampler2D poolSurface'));
      const helpers=`
        const float PI=3.141592653589793;
        float perspectiveDepthToViewZ(float d,float n,float f){return n*f/((f-n)*d-f);}
        float viewZToPerspectiveDepth(float z,float n,float f){return ((n+z)*f)/((f-n)*z);}
        vec3 inverseTransformDirection(vec3 d,mat4 m){return normalize((vec4(d,0.0)*m).xyz);}
      `;
      if(/#include\s*<(common|packing)>/.test(source))source=helpers+source.replace(/#include\s*<(common|packing)>/g,'');
      source=source.replace(/#include\s*<(tonemapping_fragment|colorspace_fragment|fog_fragment|fog_pars_fragment)>/g,'');
      source=source.replace(/#include\s*<(fog_pars_vertex|shadowmap_pars_vertex|logdepthbuf_pars_vertex|beginnormal_vertex|defaultnormal_vertex|logdepthbuf_vertex|fog_vertex|shadowmap_vertex)>/g,'');
      for(const [name,value] of Object.entries(material.defines??{})) {
        if(value!==''&&value!==undefined)source=source.replace(new RegExp(`\\b${name}\\b`,'g'),String(value));
      }
      source=source.replace(/uniform\s+highp\s+/g,'uniform ')
        .replace(/varying\s+(\w+)\s+([^;]+);/g, (_,type:string,names:string)=>names.split(',').map(name=>`varying ${type} ${name.trim()};`).join('\n'));
      source=source.replace(/#include\s*<cube_uv_reflection_fragment>/g,'');
      // GLSLDecoder expects a block around each nested loop. Match the body's
      // balanced braces so an inner if statement cannot close the outer loop.
      const nested=/for\s*\(([^)]*)\)\s*(for\s*\([^)]*\)\s*\{)/;
      for(let match=source.match(nested);match;match=source.match(nested)){
        const start=match.index!;
        const opening=start+match[0].lastIndexOf('{');
        let end=opening+1,depth=1;
        for(;depth>0&&end<source.length;end++){if(source[end]==='{')depth++;else if(source[end]==='}')depth--;}
        source=source.slice(0,end)+'}'+source.slice(end);
        source=source.slice(0,start)+`for(${match[1]}){${match[2]}`+source.slice(start+match[0].length);
      }
      // Projection matrices on the node renderer already use WebGPU's 0..1 Z.
      source=source.replace(/\b(depth|d)\s*\*\s*2\.?0?\s*-\s*1\.?0?/g,'$1')
        .replace(/clip\.z\/clip\.w\s*\*\s*\.5\s*\+\s*\.5/g,'clip.z/clip.w')
        .replace('vec4(ndc,-1.,1.)','vec4(ndc,0.,1.)');
      for (const match of source.matchAll(/attribute\s+(\w+)\s+(\w+)\s*;/g)) {
        if(!(match[2] in builtins))builtins[match[2]] = TSL.attribute(match[2], match[1]);
      }
      source = source.replace(/uniform\s+(\w+)\s+([^;]+);/g, (_, type: string, names: string) => names.split(',').map(name=>`uniform ${type} ${name.trim()};`).join('\n'))
        .replace(/\bgl_FragCoord\b/g, 'pixelCoord')
        .replace(/\bdiscard\s*;/g,'poolDiscard();')
        .replace(/attribute\s+\w+\s+\w+\s*;/g, '')
        .replace(/precision\s+\w+\s+\w+\s*;/g, '')
        .replace(/out\s+vec4\s+(outState|result)\s*;/g, '').replace(/\boutState\b/g, 'result')
        .replace(vertex ? /\bgl_Position\b/g : /\bgl_FragColor\b/g, 'result')
        .replace(/void\s+main\s*\(\s*\)\s*\{/, 'vec4 main(){vec4 result=vec4(0);for(int once=0;once<1;once++){')
        .replace(/return\s*;/g, 'break;');
      for(const name of Object.keys(builtins))source=source.replace(new RegExp(`uniform\\s+\\w+\\s+${name}\\s*;`,'g'),'');
      const end = source.lastIndexOf('}');
      source = source.slice(0, end) + '}return result;\n' + source.slice(end);
      const encoder = new TSLEncoder(); encoder.iife = true; encoder.reference = true;
      const addImport=encoder.addImport.bind(encoder);
      encoder.addImport=(name:string)=>{if(!(name in builtins))addImport(name);};
      const emitFunction=encoder.emitFunction.bind(encoder);
      encoder.emitFunction=(fn: Parameters<typeof encoder.emitFunction>[0])=>{
        const code=emitFunction(fn);
        return fn.name==='main'?code.replace(/}, \{[^{}]*return:\s*'\w+'[^{}]*} \)/g,'} )'):code;
      };
      const emitVariables=encoder.emitVariables.bind(encoder);
      encoder.emitVariables=(v:Parameters<typeof encoder.emitVariables>[0],root=true):string=>{
        const ast=v as typeof v&{getParent():{isFunctionDeclaration?:boolean}[];value:typeof v.value&{isNumericExpression?:boolean}};
        if(!ast.getParent().some(p=>p.isFunctionDeclaration))return emitVariables(v,root);
        encoder.addImport(v.type);
        const value=v.value?encoder.emitExpression(v.value as never):`${v.type}()`;
        const init=ast.value?.isNumericExpression?`${v.type}(${value})`:value;
        return `${root?'const ':''}${v.name}=(${init}).toVar()`+(v.next?', '+encoder.emitVariables(v.next,false):'');
      };
      let code: string;
      try{code = new Transpiler(new GLSLDecoder(), encoder).parse(source).trim().replace(/;$/, '')
        .replace(/Fn\( \( \[ ([^\]]+) \] \) => \{/g, (header,params:string)=>header+'\n'+params.split(',').map(p=>`${p.trim()}=${p.trim()}.toVar();`).join('\n'))
        .replace(/-\s*(\d*\.?\d+)\.(\w+)\s*\(/g, 'nodeFloat(-$1).$2(');
      }catch(error){
        throw new Error(`Node shader ${material.uuid} (${source.slice(0,140)}): ${error}`);
      }
      for(const [name,box] of Object.entries(material.uniforms)) {
        if(Array.isArray(box.value))code=code.replace(new RegExp(`\\b${name}\\[\\s*(\\d+)\\s*\\]`,'g'),`${name}.element($1)`);
      }
      const keys = Object.keys(builtins);
      const factory = new Function(...keys, `return (${code})`)(...Object.values(builtins));
      return factory(tsl, material.uniforms).main();
    };
    node.vertexNode = compile(material.vertexShader, true);
    if(material.fragmentShader.includes('gl_FragDepth')){
      node.depthNode=legacyTexture(material.uniforms.depthImage).r;
    }
    node.fragmentNode = material.name==='OutputShader'
      ? tsl.reference('value','texture' as never,material.uniforms.tDiffuse)
      : compile(material.fragmentShader.replace(/gl_FragDepth\s*=[^;]+;/g,''), false);
    return node;
  };
}
