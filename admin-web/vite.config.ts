import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Relative base so the production build works when served from a GitHub
// Pages project subpath (e.g. https://user.github.io/GuYo/) as well as
// from the root of any other static host.
export default defineConfig({
  base: './',
  plugins: [react()],
})
