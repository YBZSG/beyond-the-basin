import { defineConfig } from 'vite';
import vinext from 'vinext';

export default defineConfig({
  define: { __POOL_BENCHMARK__: 'false' },
  plugins: [vinext()],
  server: {
    watch: {
      // Only hand-written source should be watched. Everything generated or
      // tool-owned (APK staging, mimosa audit state, playwright recordings,
      // build output) gets locked or churned while held, and one EBUSY on a
      // FSWatcher takes the whole dev server down.
      ignored: [
        '**/node_modules/**',
        '**/.git/**',
        '**/apk/**',
        '**/.mimosa/**',
        '**/.playwright-cli/**',
        '**/output/**',
        '**/work/**',
        '**/dist/**',
        '**/dist-apk/**',
        '**/dist-single/**',
        '**/.next/**',
        '**/.vinext/**',
        '**/*.webm',
        '**/hinata_-_naruto_-_bikini.glb',
        '**/音效/**',
      ],
    },
  },
});
