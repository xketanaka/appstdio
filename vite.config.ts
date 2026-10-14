import { fileURLToPath } from "node:url"
import tailwindcss from "@tailwindcss/vite"
import vue from "@vitejs/plugin-vue"
import { defineConfig } from "vitest/config"
import RubyPlugin from "vite-plugin-ruby"

export default defineConfig({
  plugins: [RubyPlugin(), vue(), tailwindcss()],
  // 既定ではルート（app/javascript）の下に作られ、vboxsf 側に書き込まれる
  cacheDir: fileURLToPath(new URL("node_modules/.vite", import.meta.url)),
  server: {
    // Rails（コンテナ名 vite で届く）と、ブラウザが開くホスト名からのアクセスを許す
    allowedHosts: ["vite", ...(process.env.RAILS_DEVELOPMENT_HOSTS?.split(",") ?? [])],
    // vboxsf ではファイルの変更が通知されない
    watch: { usePolling: true, interval: 1000 },
    hmr: { clientPort: Number(process.env.VITE_LISTEN_PORT ?? 3036) },
  },
  test: {
    environment: "jsdom",
  },
})
