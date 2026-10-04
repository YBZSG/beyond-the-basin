import * as T from 'three';
import type { VoxelField } from './world';
import { type PoolRenderer, maxAnisotropy } from './backend';

/** CC0 scanned ceramic, projected in metres so scaled walls keep square tiles. */
export function createAgedTiles(renderer:PoolRenderer,field:VoxelField){
  const loader=new T.TextureLoader();
  const textures=['color','normal','roughness'].map(name=>{
    const texture=loader.load(`/assets/textures/aged-tiles/${name}.jpg`);
    texture.wrapS=texture.wrapT=T.RepeatWrapping;
    texture.anisotropy=Math.min(8,maxAnisotropy(renderer));
    return texture;
  });
  textures[0].colorSpace=T.SRGBColorSpace;
  const createMaterial=(color='#eeeee7'):T.MeshStandardMaterial=>{
  const material=new T.MeshPhysicalMaterial({
    color,map:textures[0],normalMap:textures[1],roughnessMap:textures[2],
    normalScale:new T.Vector2(.32,.32),roughness:1,metalness:0,envMapIntensity:1.1,
    clearcoat:.7,clearcoatRoughness:.1,clearcoatNormalMap:textures[1],clearcoatNormalScale:new T.Vector2(.22,.22),
  });
  field.apply(material);
  material.userData.poolAged={textures};
  const before=material.onBeforeCompile;
  material.onBeforeCompile=(shader,renderer)=>{
    before.call(material,shader,renderer);
    // Point lights approximate fluorescent illumination, but have no emitting
    // surface and produced detached white blobs on the glaze. Keep their
    // diffuse/shadow contribution; fixture-shaped specular comes from the
    // captured emissive tube geometry (environment and live reflection).
    const direct='RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );';
    shader.fragmentShader=shader.fragmentShader.replace(direct,`{
      vec3 ceramicSpecular=reflectedLight.directSpecular;
      vec3 ceramicCoat=clearcoatSpecularDirect;
      ${direct}
      reflectedLight.directSpecular=ceramicSpecular;
      clearcoatSpecularDirect=ceramicCoat;
    }`);
    // The original scan is diagonal. Rotate all three maps together, retaining
    // their registered grout and surface wear, with roughly 20 cm tiles.
    shader.fragmentShader=shader.fragmentShader.replace('#include <map_fragment>',`
      vec3 agedFace=abs(normalize(cross(dFdx(vPoolWorld),dFdy(vPoolWorld))));
      vec2 agedPlane=agedFace.y>.6?vPoolWorld.xz:(agedFace.x>.6?vPoolWorld.zy:vPoolWorld.xy);
      vec2 agedUv=mat2(.707107,-.707107,.707107,.707107)*agedPlane*1.2;
      vec3 agedColor=texture2D(map,agedUv).rgb;
      float agedLuma=dot(agedColor,vec3(.2126,.7152,.0722));
      diffuseColor.rgb*=mix(vec3(pow(agedLuma,.72)),agedColor,.035)*1.08;
      float agedStain=sin(vPoolWorld.x*1.7+sin(vPoolWorld.z*.8))*sin(vPoolWorld.y*3.1+vPoolWorld.z);
      float agedWaterline=exp(-abs(vPoolWorld.y-.36)*10.0)*(.07+.035*agedStain);
      diffuseColor.rgb*=mix(vec3(1.0),vec3(.64,.71,.56),agedWaterline);
    `);
    shader.fragmentShader=shader.fragmentShader.replace('#include <roughnessmap_fragment>',`
      ${T.ShaderChunk.roughnessmap_fragment.replaceAll('vRoughnessMapUv','agedUv')}
      float agedWet=exp(-max(vPoolWorld.y-.32,0.0)*.8);
      float agedDrip=.5+.5*sin(agedPlane.x*8.0+sin(agedPlane.x*2.3)+sin(agedPlane.y*.6)*.3);
      roughnessFactor=clamp(roughnessFactor*.28+.08-.065*agedWet-.025*agedDrip,.09,.38);
    `);
    shader.fragmentShader=shader.fragmentShader.replace('#include <normal_fragment_begin>',T.ShaderChunk.normal_fragment_begin.replaceAll('vNormalMapUv','agedUv').replaceAll('vClearcoatNormalMapUv','agedUv'));
    shader.fragmentShader=shader.fragmentShader.replace('#include <normal_fragment_maps>',T.ShaderChunk.normal_fragment_maps.replaceAll('vNormalMapUv','agedUv'));
    shader.fragmentShader=shader.fragmentShader.replace('#include <clearcoat_normal_fragment_maps>',T.ShaderChunk.clearcoat_normal_fragment_maps.replaceAll('vClearcoatNormalMapUv','agedUv'));
  };
  material.customProgramCacheKey=()=> 'pool-aged-wet-white-tiles-3';
  return material;
  };
  return {material:createMaterial('#e0e3dc'),createMaterial,textures};
}
