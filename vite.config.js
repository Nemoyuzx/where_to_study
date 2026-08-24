import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const host = process.env.TAURI_DEV_HOST
const platform = process.env.TAURI_ENV_PLATFORM
const webviewTarget = platform === 'windows' || platform === 'android' ? 'chrome105' : 'safari15'

export default defineConfig({
  plugins: [
    react(),
    {
      // Preview/dev browser builds have no Tauri CSP header, so inject the
      // production-aligned policy (minus Tauri IPC schemes) only while serving.
      // frame-ancestors is intentionally omitted because browsers ignore that
      // directive in a meta policy; the packaged app still enforces it through
      // Tauri's response-level CSP.
      name: 'dev-preview-csp',
      apply: 'serve',
      transformIndexHtml(html) {
        return html.replace(
          '<head>',
          [
            '<head>',
            '    <meta http-equiv="Content-Security-Policy" content="default-src \'self\'; script-src \'self\' \'unsafe-inline\'; worker-src \'self\' blob:; style-src \'self\' \'unsafe-inline\'; img-src \'self\' data:; connect-src \'self\' ws: http://localhost:* http://127.0.0.1:*; object-src \'none\'; base-uri \'self\'" />',
          ].join('\n'),
        )
      },
    },
  ],
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: 'ws',
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      ignored: ['**/src-tauri/**'],
    },
  },
  envPrefix: ['VITE_', 'TAURI_ENV_*'],
  build: {
    target: webviewTarget,
    minify: !process.env.TAURI_ENV_DEBUG ? 'esbuild' : false,
    sourcemap: !!process.env.TAURI_ENV_DEBUG,
  },
})
