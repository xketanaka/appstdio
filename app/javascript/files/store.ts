import { reactive } from "vue"
import { api, type FolderPayload, type SectionKey, type Tree, type TreeFolder } from "./api"
import { setMessages, t, type Messages } from "./i18n"

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
  // 開いているフォルダ。ドライブのルートやゴミ箱などを開いているときは null
  currentFolderId: null as number | null,
  tree: null as Tree | null,
  // ツリーに読み込んだ、親フォルダの id ごとの直下のフォルダ。ドライブのルートの分も入る
  children: new Map<number, TreeFolder[]>(),
  openSections: new Set<SectionKey>(),
  openFolders: new Set<number>(),
  // 作成・移動などで中身が変わるたびに増える。開いている画面はこれを見て読み直す
  revision: 0,
  // 画面の下に一時的に出す知らせ（移動した、移せなかった、など）
  notice: null as { message: string, error: boolean } | null,
})

let noticeTimer: ReturnType<typeof setTimeout> | undefined

export function notify(message: string, { error = false } = {}) {
  state.notice = { message, error }
  clearTimeout(noticeTimer)
  noticeTimer = setTimeout(() => (state.notice = null), 6000)
}

export function loadConfig(element: HTMLElement) {
  const value: Config = JSON.parse(element.dataset.config ?? "{}")
  setMessages(value.messages)
  config.title_prefix = value.title_prefix
  config.admin_or_owner = value.admin_or_owner
  state.privileged = value.privileged
}

const rootIds = () => [state.tree?.shared_drive?.id, state.tree?.my_drive?.id].filter((id) => id !== undefined)

async function loadChildren(parentIds: number[], { force = false } = {}) {
  const ids = force ? parentIds : parentIds.filter((id) => !state.children.has(id))
  if (ids.length === 0) return

  const loaded = await api.treeChildren(ids)
  ids.forEach((id) => {
    // 閲覧できなくなった、消えたなどで応答に無い親は、読み込んでいない扱いに戻す
    const folders = loaded[id]
    if (folders) state.children.set(id, folders)
    else state.children.delete(id)
  })
}

// 作成・移動・特権モードの切り替えのあとにも呼ぶ。読み込み済みの階層もまとめて読み直す
export async function reloadTree() {
  state.tree = await api.tree()
  const roots = [state.tree.shared_drive, state.tree.my_drive].filter((root) => root !== null)
  roots.forEach((root) => state.children.set(root.id, root.folders))

  const loaded = [...state.children.keys()].filter((id) => !rootIds().includes(id))
  await loadChildren(loaded, { force: true })
}

// 中身が変わったことを、開いている画面とツリーに知らせる
export async function changed() {
  state.revision++
  await reloadTree()
}

type Item = { id: number, name: string }

// 移す。失敗したら例外をそのまま投げるので、理由の出し方は呼び出し側で決める
export async function moveItems(items: Item[], destination: { id: number, label: string }) {
  await api.move(items.map((item) => item.id), destination.id)
  notify(items.length === 1
    ? t("move.done_one", { name: items[0].name, destination: destination.label })
    : t("move.done_other", { count: items.length, destination: destination.label }))
  await changed()
}

export async function toggleFolder(id: number) {
  if (state.openFolders.has(id)) {
    state.openFolders.delete(id)
    return
  }
  state.openFolders.add(id)
  await loadChildren([id])
}

// 開いている場所の区分を示し、左ペインでその区分を開く。利用者が開いた他の区分は閉じない
export function showSection(section: SectionKey, title: string) {
  state.section = section
  state.currentFolderId = null
  state.openSections.add(section)
  document.title = [config.title_prefix, title].filter(Boolean).join(" - ")
}

// フォルダを開いたとき、左ペインでそこまでの祖先を開いて、そのフォルダを示す。
// 祖先をたどれない（共有されたアイテムから開いた）ときは「共有されたアイテム」を示す
export async function showFolder(payload: FolderPayload) {
  const root = payload.breadcrumbs.length === 0 && !payload.via_shared
  showSection(payload.via_shared ? "shared_with_me" : payload.section, payload.folder.label)
  if (root || payload.via_shared) return

  state.currentFolderId = payload.folder.id
  const ancestors = payload.breadcrumbs.slice(1).map((crumb) => crumb.id)
  ancestors.forEach((id) => state.openFolders.add(id))
  await loadChildren(ancestors)
}
