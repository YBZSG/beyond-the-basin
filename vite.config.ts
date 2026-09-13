import { defineConfig } from 'vite';
import vinext from 'vinext';

export default defineConfig({
  plugins: [vinext()],
  server: {
    watch: {
      // The APK pipeline stages audio/assets into apk/stage and holds the
      // files locked; the mimosa audit and playwright tooling churn their own
      // state directories. Watching any of them crashes the server with EBUSY.
      ignored: ['**/apk/**', '**/.mimosa/**', '**/.playwright-cli/**'],
    },
  },
});
