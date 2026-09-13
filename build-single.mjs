// Folds the vite single build (dist-single/stage) into one self-contained
// HTML file: JS and CSS are inlined, the water-normal texture is swapped for
// a data URI, and every sfx clip is served from an in-memory fetch shim.
// The result needs no other files and runs from file:// or any static host.
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const stage = 'dist-single/stage';
const outFile = 'dist-single/BEYOND-THE-BASIN-PoolCore-single.html';

const read = (p, enc) => readFileSync(p, enc);
const dataUri = (p) => {
    const m = p.endsWith('.ogg') ? 'audio/ogg' : p.endsWith('.jpg') ? 'image/jpeg' : 'application/octet-stream';
    return `data:${m};base64,${read(p).toString('base64')}`;
};
const must = (ok, what) => { if (!ok) throw new Error(`single-file build: ${what} missing`); };

must(readdirSync(stage).length > 0, `${stage} is empty - run the vite.single.config.ts build first`);
let html = read(join(stage, 'index.html'), 'utf8');

// 1. Stylesheets -> <style>.
html = html.replace(/<link[^>]*rel="stylesheet"[^>]*>/g, (tag) => {
    const href = tag.match(/href="([^"]+)"/)?.[1];
    must(href, 'stylesheet link without href');
    const css = read(join(stage, href.replace(/^\.\//, '')), 'utf8').replace(/<\/style/gi, '<\\/style');
    return `<style>${css}</style>`;
});

// 2. Entry module script -> inline <script> with a fetch shim for /assets/sfx
//    prepended so PoolAudio loads the embedded clips. The texture path is
//    replaced with a data URI because TextureLoader loads through Image, not
//    fetch.
const scriptTag = html.match(/<script type="module"[^>]*src="([^"]+)"[^>]*><\/script>/);
must(scriptTag, 'module entry script not found');
const jsFile = scriptTag[1].replace(/^\.\//, '');
let js = read(join(stage, jsFile), 'utf8');

const sfxDir = 'public/assets/sfx';
const files = {};
for (const f of readdirSync(sfxDir)) {
    if (f.endsWith('.ogg')) files[`/assets/sfx/${f}`] = dataUri(join(sfxDir, f));
}
const sfxCount = Object.keys(files).length;
must(sfxCount >= 12, `only ${sfxCount} sfx clips found`);

const texUri = dataUri('public/assets/textures/waternormals.jpg');
const texPath = '/assets/textures/waternormals.jpg';
// esbuild may keep the literal as ", ' or ` quoted - cover all forms.
const texVariants = [`"${texPath}"`, `'${texPath}'`, '`' + texPath + '`'];
const texFound = texVariants.some((v) => js.includes(v));
must(texFound, 'water normals texture literal not found in bundle');
for (const v of texVariants) js = js.split(v).join(JSON.stringify(texUri));

const shim = `window.__POOL_ASSETS=${JSON.stringify(files)};` +
    `(function(){var f=window.fetch&&window.fetch.bind(window);if(!f)return;` +
    `window.fetch=function(i,n){try{var u=typeof i==='string'?i:i&&i.url;` +
    `var h=u&&window.__POOL_ASSETS[u];if(h)return f(h,n);}catch(e){}return f(i,n);};})();`;

js = shim + js.replace(/<\/script/gi, '<\\/script');
// Function replacement: a string argument would treat $& / $' sequences in
// the bundle as substitution patterns and corrupt the output.
html = html.replace(scriptTag[0], () => `<script type="module">${js}</script>`);

mkdirSync('dist-single', { recursive: true });
writeFileSync(outFile, html);
console.log(`single-file HTML written: ${outFile} (${(html.length / 1048576).toFixed(2)} MB, ${sfxCount} sfx clips embedded)`);
