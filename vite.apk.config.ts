import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

// Static client bundle for the Android WebView APK. The app is served from
// https://appassets.androidplatform.net/... which MainActivity maps onto the
// APK assets/ folder, so absolute /assets/... URLs keep working.
export default defineConfig({
  root: 'apk/www',
  base: '/',
  // Runtime fetches live at /assets/sfx, /assets/textures (and /assets/models);
  // reuse the web project's public/ so the APK ships the same files.
  publicDir: fileURLToPath(new URL('./public', import.meta.url)),
  plugins: [react()],
  build: {
    // Output lands at the APK assets root; MainActivity serves /X from asset
    // file X, so /assets/index-*.js (vite's default assetsDir) and
    // /assets/textures/... both map 1:1. build-apk.ps1 moves index.html to
    // stage/www/index.html afterwards.
    outDir: '../stage',
    emptyOutDir: true,
    target: 'es2020',
    chunkSizeWarningLimit: 4096,
  },
});
