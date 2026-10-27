import { DirectUpload } from "@rails/activestorage"
import { reactive } from "vue"
import { api, ForbiddenError, NotFoundError, ValidationError, type Uploaded } from "./api"
import { formatSize } from "./format"
import { t } from "./i18n"
import { changed, config } from "./store"

export type Upload = {
  id: number
  name: string
  size: number
  loaded: number
  destination: string
  status: "waiting" | "preparing" | "uploading" | "done" | "error"
  message: string | null
  // 登録した結果。新しい版になったときは、版の番号で知らせる（新しいファイルと取り違えないように）
  saved: Uploaded | null
}

// 画面の右下に出す、アップロードの一覧。フォルダを移っても続ける（画面をまたいで持つ）
export const uploads = reactive<Upload[]>([])

let nextId = 0
let running = false

// 送り先。1段目（送り先をもらう）の URL と、2段目（登録）の呼び出し
type Target = { label: string, prepareUrl: string, complete: (signedBlobId: string) => Promise<Uploaded> }
const queue: { upload: Upload, file: File, target: Target }[] = []

// フォルダへ上げる。同じ名前のファイルがあれば、サーバがその新しい版にする
export function uploadFiles(files: File[], destination: { id: number, label: string }) {
  files.forEach((file) => enqueue(file, {
    label: destination.label,
    prepareUrl: `/files/api/nodes/prepare_upload?parent_id=${destination.id}`,
    complete: (signedBlobId) => api.completeUpload(destination.id, signedBlobId),
  }))
}

// ファイルの新しい版として上げる。上げたファイルの名前は使わない
export function uploadVersion(file: File, target: { id: number, name: string }) {
  enqueue(file, {
    label: target.name,
    prepareUrl: `/files/api/nodes/${target.id}/versions/prepare_upload`,
    complete: (signedBlobId) => api.addVersion(target.id, signedBlobId),
  })
}

function enqueue(file: File, target: Target) {
  const upload = reactive<Upload>({
    id: ++nextId, name: file.name, size: file.size, loaded: 0, destination: target.label,
    status: "waiting", message: null, saved: null,
  })
  uploads.push(upload)
  // 大きすぎるものは、中身を読んで送り始める前に断る（サーバも同じ上限で断る）
  if (file.size > config.max_upload_bytes) fail(upload, t("upload.too_large", { max: formatSize(config.max_upload_bytes) }))
  else queue.push({ upload, file, target })
  run()
}

// 1件ずつ送る。まとめて送ると、大きなファイルがあるとき全部が遅くなる
async function run() {
  if (running) return
  running = true
  for (let next = queue.shift(); next; next = queue.shift()) {
    await uploadOne(next.upload, next.file, next.target)
  }
  running = false
}

async function uploadOne(upload: Upload, file: File, target: Target) {
  upload.status = "preparing"
  let blobRequest: XMLHttpRequest | null = null
  const direct = new DirectUpload(file, target.prepareUrl, {
    directUploadWillCreateBlobWithXHR: (xhr) => (blobRequest = xhr),
    directUploadWillStoreFileWithXHR: (xhr) => {
      upload.status = "uploading"
      xhr.upload.addEventListener("progress", (event) => (upload.loaded = event.loaded))
    },
  })

  const blob = await new Promise<{ signed_id: string } | null>((resolve) => {
    direct.create((error, created) => {
      if (error === null && created) resolve(created)
      else {
        fail(upload, prepareError(blobRequest), error)
        resolve(null)
      }
    })
  })
  if (blob === null) return

  try {
    upload.saved = await target.complete(blob.signed_id)
    upload.status = "done"
    upload.loaded = upload.size
    await changed()
  } catch (error) {
    fail(upload, completeError(error), error)
  }
}

// 1段目（送り先をもらう）で断られたときの理由。DirectUpload は理由を文字列にしか渡さないので、
// 要求の応答から読む
function prepareError(xhr: XMLHttpRequest | null) {
  if (xhr?.status === 422) return (xhr.response?.errors ?? []).join(" ") || t("upload.failed")
  if (xhr?.status === 403) return t("upload.forbidden")
  if (xhr?.status === 404) return t("upload.not_found")
  return t("upload.failed")
}

function completeError(error: unknown) {
  if (error instanceof ValidationError) return error.messages.join(" ")
  if (error instanceof ForbiddenError) return t("upload.forbidden")
  if (error instanceof NotFoundError) return t("upload.not_found")
  return t("upload.failed")
}

function fail(upload: Upload, message: string, cause?: unknown) {
  upload.status = "error"
  upload.message = message
  // 理由が分かっている断りは出さない。分からない失敗だけ、調べられるよう残す
  if (cause !== undefined && message === t("upload.failed")) console.error(cause)
}

// 終わったもの（成功・失敗）を一覧から片付ける。送っている途中のものは残す
export function clearFinished() {
  for (let i = uploads.length - 1; i >= 0; i--) {
    if (uploads[i].status === "done" || uploads[i].status === "error") uploads.splice(i, 1)
  }
}
