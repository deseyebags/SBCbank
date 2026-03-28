import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    proxy: {
      '/api/auth': {
        target: 'http://localhost:8001',
        changeOrigin: true,
        rewrite: (routePath) => routePath.replace(/^\/api/, ''),
      },
      '/api/accounts': {
        target: 'http://localhost:8001',
        changeOrigin: true,
        rewrite: (routePath) => routePath.replace(/^\/api/, ''),
      },
      '/api/payments': {
        target: 'http://localhost:8002',
        changeOrigin: true,
        rewrite: (routePath) => routePath.replace(/^\/api/, ''),
      },
      '/api/ledger': {
        target: 'http://localhost:8003',
        changeOrigin: true,
        rewrite: (routePath) => routePath.replace(/^\/api/, ''),
      },
      '/api/statements': {
        target: 'http://localhost:8004',
        changeOrigin: true,
        rewrite: (routePath) => routePath.replace(/^\/api/, ''),
      },
    },
  },
})
