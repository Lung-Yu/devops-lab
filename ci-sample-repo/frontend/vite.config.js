import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 開發時（npm run dev）把 API 轉給本機跑的後端；正式建置的檔案放進後端的 wwwroot，同一個網址，不需要 CORS
export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      '/api': 'http://localhost:5000',
      '/health': 'http://localhost:5000',
    },
  },
})
