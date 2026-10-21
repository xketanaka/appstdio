// サーバ（app/controllers/files/api）が返す JSON の形。Ruby 側を変えたら合わせること

export type SectionKey = "shared_drive" | "shared_with_me" | "my_drive" | "trash"

export type TreeFolder = { id: number, name: string, readable: boolean }

export type Tree = { shared_drive: TreeFolder[], my_drive: TreeFolder[] }

export type Entry = {
  id: number
  kind: "folder" | "file"
  name: string
  readable: boolean
  owner: string | null
  updated_at: string | null
  byte_size: number | null
}

export type TrashEntry = {
  id: number
  kind: "folder" | "file"
  name: string
  deleted_by: string | null
  deleted_at: string
  byte_size: number | null
}

export type FolderLink = { id: number, label: string }

export type FolderPayload = {
  folder: FolderLink
  section: SectionKey
  breadcrumbs: FolderLink[]
  via_shared: boolean
  can_edit: boolean
  entries: Entry[]
}

export type FolderSource = { drive: "shared" | "mine" } | { id: string }

export class NotFoundError extends Error {}

const csrfToken = () => document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")?.content ?? ""

async function request<T>(method: string, path: string): Promise<T> {
  const response = await fetch(path, {
    method,
    headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken() },
  })
  if (response.status === 401) {
    // ログインが切れた。読み直せば、入れ物のページがログイン画面などへ転送する
    window.location.reload()
    return new Promise(() => {})
  }
  if (response.status === 404) throw new NotFoundError(path)
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status}`)

  return response.status === 204 ? (undefined as T) : response.json()
}

export const api = {
  tree: () => request<Tree>("GET", "/files/api/tree"),
  folder: (source: FolderSource) =>
    request<FolderPayload>("GET", "id" in source ? `/files/api/folders/${source.id}` : `/files/api/drives/${source.drive}`),
  sharedItems: () => request<{ entries: Entry[] }>("GET", "/files/api/shared"),
  trash: () => request<{ entries: TrashEntry[] }>("GET", "/files/api/trash"),
  enterPrivilegedMode: () => request<void>("POST", "/files/api/privileged_mode"),
  leavePrivilegedMode: () => request<void>("DELETE", "/files/api/privileged_mode"),
}
