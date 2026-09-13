import { defineConfig } from 'vite';
import vinext from 'vinext';

export default defineConfig({
  plugins: [vinext()],
  server: {
    watch: {
      // The APK pipeline stages audio/assets into apk/stage and holds the
      // files locked; watching them crashes the dev server with EBUSY.
      ignored: ['**/apk/**'],
    },
  },
});
