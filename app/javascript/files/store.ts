import { reactive } from "vue"
import { api, type SectionKey, type Tree } from "./api"
import { setMessages, type Messages } from "./i18n"

// 入れ物のページ（app/views/files/app/show.html.erb）が data-config で渡すもの
type Config = {
  messages: Messages
  title_prefix: string
  admin_or_owner: boolean
  privileged: boolean
}

export const config = { title_prefix: "", admin_or_owner: false }

// 画面をまたいで保つ状態。左ペインはスマホとPCの2箇所に描くので、開閉もここに持って揃える
export const state = reactive({
  privileged: false,
  section: null as SectionKey | null,
  tree: null as Tree | null,
  openSections: new Set<SectionKey>(),
})

export function loadConfig(element: HTMLElement) {
  const value: Config = JSON.parse(element.dataset.config ?? "{}")
  setMessages(value.messages)
  config.title_prefix = value.title_prefix
  config.admin_or_owner = value.admin_or_owner
  state.privileged = value.privileged
}

export async function reloadTree() {
  state.tree = await api.tree()
}

// 開いている場所の区分を示し、左ペインでその区分を開く。利用者が開いた他の区分は閉じない
export function showSection(section: SectionKey, title: string) {
  state.section = section
  state.openSections.add(section)
  document.title = [config.title_prefix, title].filter(Boolean).join(" - ")
}
