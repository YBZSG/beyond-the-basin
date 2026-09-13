import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

// Single-file HTML build: same entry as the APK bundle, but everything merged
// into one JS chunk (PoolVCT lazy-loads the engine, so the default build splits
// it). build-single.mjs then folds JS/CSS and runtime-fetched assets into the
// HTML itself.
export default defineConfig({
  root: 'apk/www',
  base: './',
  publicDir: fileURLToPath(new URL('./public', import.meta.url)),
  plugins: [react()],
  build: {
    outDir: fileURLToPath(new URL('./dist-single/stage', import.meta.url)),
    emptyOutDir: true,
    target: 'es2020',
    chunkSizeWarningLimit: 8192,
    rollupOptions: { output: { inlineDynamicImports: true } },
  },
});
