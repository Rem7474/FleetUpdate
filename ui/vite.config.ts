import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const allowedHostsEnv = (env.ALLOWED_HOSTS || '')
    .split(',')
    .map((h) => h.trim())
    .filter(Boolean)
  const defaultAllowed = ['localhost', '127.0.0.1', 'erpnext.remcorp.fr']
  const allowedHosts = Array.from(new Set([...defaultAllowed, ...allowedHostsEnv]))

  return {
    plugins: [react()],
    server: {
      port: 5173,
      strictPort: true,
      host: true,
      allowedHosts,
      proxy: {
        '/api': {
          target: 'http://localhost:8000',
          changeOrigin: true,
        },
      },
    },
  }
})
