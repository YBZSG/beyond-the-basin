/** Touch hardware detection shared by the engine and the React shell.
 * A dev-only `?touch=1` URL flag forces the mobile layout for local testing. */
export const isTouchDevice=()=>typeof window!=='undefined'&&(window.matchMedia?.('(pointer: coarse)').matches||'ontouchstart' in window||(process.env.NODE_ENV!=='production'&&new URLSearchParams(location.search).has('touch')));
/** Maps an analog stick vector to the same key codes the desktop WASD path reads.
 * Dead zone .35; pushing past .9 counts as the shift sprint. */
export function stickToKeys(x:number,y:number,keys:Set<string>){
  for(const k of ['KeyW','KeyA','KeyS','KeyD','ShiftLeft'])keys.delete(k);
  if(Math.hypot(x,y)<.35)return;
  if(Math.abs(x)>.35)keys.add(x>0?'KeyD':'KeyA');
  if(Math.abs(y)>.35)keys.add(y>0?'KeyS':'KeyW');
  if(Math.hypot(x,y)>.9)keys.add('ShiftLeft');
}
