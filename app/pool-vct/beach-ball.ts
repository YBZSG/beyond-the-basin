import * as T from 'three';

export const BEACH_BALL_RADIUS = .21;

// One continuous surface: panel colours never alter the shape or its origin.
export function createBeachBallGeometry() {
  return new T.SphereGeometry(BEACH_BALL_RADIUS, 64, 48);
}

export function createBeachBallTexture() {
  const width=1024,height=512,data=new Uint8Array(width*height*4);
  const panels=[[220,62,46],[245,242,222],[32,134,192],[245,242,222],[245,199,43],[245,242,222]];
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const u=x/width*6,v=y/(height-1),edge=Math.min(u%1,1-u%1);
    const cap=v<.045||v>.955;
    const color=cap?panels[1]:panels[Math.floor(u)];
    // A narrow welded seam, with a soft highlight along the inflated panel.
    const shade=cap?1:1-.16*Math.exp(-edge*edge/.00008)+.025*Math.exp(-Math.pow(edge-.018,2)/.0001);
    const i=(x+y*width)*4;
    for(let c=0;c<3;c++)data[i+c]=Math.min(255,Math.round(color[c]*shade));
    data[i+3]=255;
  }
  const texture=new T.DataTexture(data,width,height,T.RGBAFormat);
  texture.colorSpace=T.SRGBColorSpace;texture.wrapS=T.RepeatWrapping;
  texture.magFilter=T.LinearFilter;texture.minFilter=T.LinearMipmapLinearFilter;
  texture.generateMipmaps=true;texture.needsUpdate=true;
  return texture;
}
