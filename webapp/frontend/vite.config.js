import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 3000,
    proxy: {
      '/api': 'http://yt_agent_backend:8000',
      '/health': 'http://yt_agent_backend:8000'
    }
  }
})
