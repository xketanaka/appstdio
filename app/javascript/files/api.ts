// サーバ（app/controllers/files/api）が返す JSON の形。Ruby 側を変えたら合わせること

export type SectionKey = "shared_drive" | "shared_with_me" | "my_drive" | "trash"

export type TreeFolder = { id: number, name: string, readable: boolean, has_children: boolean }

// ドライブのルートの id と直下のフォルダ。マイドライブは初めて開くまで無い
export type TreeRoot = { id: number, folders: TreeFolder[] }

export type Tree = { shared_drive: TreeRoot | null, my_drive: TreeRoot | null }

export type Entry = {
  id: number
  kind: "folder" | "file"
  name: string
  readable: boolean
  // そのもの自身を編集できるか（ファイルなら新しい版を足せるか）
  editable: boolean
  // 共有設定を変えられるか（そのもの自身の管理者か）
  manageable: boolean
  owner: string | null
  updated_at: string | null
  byte_size: number | null
}

export type Version = {
  id: number
  number: number
  label: string | null
  byte_size: number
  creator: string | null
  created_at: string
  current: boolean
  purged: boolean
}

// アップロードを登録した結果。同じ名前のファイルの新しい版になったときは、その版の番号が入る
export type Uploaded = { id: number, name: string, version: number | null }

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
  can_manage: boolean
  entries: Entry[]
}

export type Role = "viewer" | "editor" | "manager"

// suspended は利用停止中の人・グループ。停止中のグループへの設定は効かないが、行は残る。
// deleted は利用者管理で削除された人。削除しても、その人に付けた権限の設定は消さずに残す
// （同じメールアドレスで追加し直すと元の所属に戻り、その設定がまた効く）。
// path はグループの最上位から自分までの名前の並び（人は null）
export type Subject = {
  type: "group" | "tenant_user"
  id: number
  name: string
  everyone: boolean
  suspended: boolean
  deleted: boolean
  path: string[] | null
}

// 継承元（from）は、上位のフォルダが見えない人には null
export type InheritedSetting = { subject: Subject, role: Role, from: FolderLink | null, cancelled: boolean }

export type Sharing = { inherited: InheritedSetting[], own: { subject: Subject, role: Role }[] }

// 加える相手の候補。detail は人のメールアドレス
export type ShareCandidate = Subject & { detail: string | null }

// role が null ならこのものの設定を消す（継承に戻す）。"none" は継承の打ち消し
export type SharingChange = { subject_type: Subject["type"], subject_id: number, role: Role | "none" | null }

export type FolderSource = { drive: "shared" | "mine" } | { id: string }

export class NotFoundError extends Error {}

export class ForbiddenError extends Error {}

// 入力の誤り（422）。messages はそのまま画面に出せる文
export class ValidationError extends Error {
  constructor(readonly messages: string[]) {
    super(messages.join(" "))
  }
}

const csrfToken = () => document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")?.content ?? ""

async function request<T>(method: string, path: string, body?: object): Promise<T> {
  const response = await fetch(path, {
    method,
    headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
    body: body && JSON.stringify(body),
  })
  if (response.status === 401) {
    // ログインが切れた。読み直せば、入れ物のページがログイン画面などへ転送する
    window.location.reload()
    return new Promise(() => {})
  }
  if (response.status === 403) throw new ForbiddenError(path)
  if (response.status === 404) throw new NotFoundError(path)
  if (response.status === 422) throw new ValidationError((await response.json()).errors)
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status}`)

  return response.status === 204 ? (undefined as T) : response.json()
}

// ダウンロードはサーバが保存先の期限付き URL へ転送するので、この URL へ移るだけでよい
export const downloadUrl = (id: number) => `/files/api/nodes/${id}/download`
export const versionDownloadUrl = (nodeId: number, versionId: number) =>
  `/files/api/nodes/${nodeId}/versions/${versionId}/download`

export const api = {
  tree: () => request<Tree>("GET", "/files/api/tree"),
  // 閲覧できない親は応答に含まれない
  treeChildren: (parentIds: number[]) =>
    request<Record<string, TreeFolder[]>>(
      "GET", `/files/api/tree/children?${parentIds.map((id) => `parent_ids[]=${id}`).join("&")}`,
    ),
  folder: (source: FolderSource) =>
    request<FolderPayload>("GET", "id" in source ? `/files/api/folders/${source.id}` : `/files/api/drives/${source.drive}`),
  createFolder: (parentId: number, name: string) =>
    request<{ id: number, name: string }>("POST", "/files/api/folders", { parent_id: parentId, name }),
  completeUpload: (parentId: number, signedBlobId: string) =>
    request<Uploaded>("POST", "/files/api/nodes/upload", { parent_id: parentId, signed_blob_id: signedBlobId }),
  versions: (nodeId: number) => request<{ can_edit: boolean, versions: Version[] }>("GET", `/files/api/nodes/${nodeId}/versions`),
  addVersion: (nodeId: number, signedBlobId: string) =>
    request<Uploaded>("POST", `/files/api/nodes/${nodeId}/versions`, { signed_blob_id: signedBlobId }),
  updateVersionLabel: (nodeId: number, versionId: number, label: string) =>
    request<void>("PATCH", `/files/api/nodes/${nodeId}/versions/${versionId}`, { label }),
  restoreVersion: (nodeId: number, versionId: number) =>
    request<{ version: number }>("POST", `/files/api/nodes/${nodeId}/versions/${versionId}/restore`),
  rename: (id: number, name: string) => request<void>("PATCH", `/files/api/nodes/${id}/rename`, { name }),
  trashNodes: (nodeIds: number[]) => request<void>("POST", "/files/api/nodes/trash", { node_ids: nodeIds }),
  restoreNodes: (nodeIds: number[]) => request<void>("POST", "/files/api/nodes/restore", { node_ids: nodeIds }),
  move: (nodeIds: number[], destinationId: number) =>
    request<void>("POST", "/files/api/nodes/move", { node_ids: nodeIds, destination_id: destinationId }),
  sharing: (nodeId: number) => request<Sharing>("GET", `/files/api/nodes/${nodeId}/permissions`),
  updateSharing: (nodeId: number, changes: SharingChange[]) =>
    request<void>("PATCH", `/files/api/nodes/${nodeId}/permissions`, { changes }),
  shareCandidates: (query: string) =>
    request<{ candidates: ShareCandidate[] }>("GET", `/files/api/share_candidates?q=${encodeURIComponent(query)}`),
  sharedItems: () => request<{ entries: Entry[] }>("GET", "/files/api/shared"),
  trash: () => request<{ entries: TrashEntry[] }>("GET", "/files/api/trash"),
  enterPrivilegedMode: () => request<void>("POST", "/files/api/privileged_mode"),
  leavePrivilegedMode: () => request<void>("DELETE", "/files/api/privileged_mode"),
}
