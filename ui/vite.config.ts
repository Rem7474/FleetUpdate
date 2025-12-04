import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const allowedHosts = (env.ALLOWED_HOSTS || '')
    .split(',')
    .map((h) => h.trim())
    .filter(Boolean)

  return {
    plugins: [react()],
    server: {
      port: 5173,
      strictPort: true,
      host: true,
      allowedHosts: allowedHosts.length > 0 ? allowedHosts : ['erpnext.remcorp.fr'],
      proxy: {
        '/api': {
          target: 'http://localhost:8000',
          changeOrigin: true,
        },
      },
    },
  }
})
