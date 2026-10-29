import { downloadUrl } from "./api"
import type { Row } from "./rows"
import { state } from "./store"
import { uploadVersion } from "./uploads"

// 行のメニューからの、ファイルへの操作。フォルダの画面と共有されたアイテムの画面の両方で使う

// サーバが保存先の期限付き URL へ転送するので、この URL へ移るだけでよい
export function download(row: Row) {
  window.location.href = downloadUrl(row.id)
}

// 版の履歴を開く（App の VersionsPanel が state.versionsOf を見て出す）
export function showVersions(row: Row) {
  state.versionsOf = { id: row.id, name: row.name }
}

// 共有設定を開く（App の ShareDialog が state.sharingOf を見て出す）
export function showSharing(target: { id: number, name: string, kind: "folder" | "file" }) {
  state.sharingOf = { id: target.id, name: target.name, kind: target.kind }
}

// 新しい版にするファイルを選ばせる。選んだら、そのファイルの新しい版として上げる
export function chooseNewVersion(row: Row) {
  const input = document.createElement("input")
  input.type = "file"
  input.addEventListener("change", () => {
    const file = input.files?.[0]
    if (file) uploadVersion(file, { id: row.id, name: row.name })
  })
  input.click()
}
