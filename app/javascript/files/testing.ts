import { readFileSync } from "node:fs"
import { createMemoryHistory, createRouter } from "vue-router"
import { parse } from "yaml"
import { setMessages } from "./i18n"

// テストで部品を描くための下ごしらえ。文言は本物の ja.files_app.yml を使い、キーの漏れも拾う
// jsdom の下では import.meta.url が file: でないので、プロジェクトのルート（npm を動かす場所）から辿る
const locale = parse(readFileSync("config/locales/ja.files_app.yml", "utf8"))
setMessages(locale.ja.files_app)

export function testRouter() {
  const Blank = { template: "<div />" }
  return createRouter({
    history: createMemoryHistory(),
    routes: ["shared_drive", "my_drive", "shared_with_me", "trash"].map((name) => ({ path: `/${name}`, name, component: Blank }))
      .concat({ path: "/folders/:id", name: "folder", component: Blank }),
  })
}
