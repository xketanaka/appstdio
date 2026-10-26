import "./testing"
import { flushPromises } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api } from "./api"
import { config } from "./store"
import { clearFinished, uploadFiles, uploads } from "./uploads"

type Created = (error: string | null, blob?: { signed_id: string }) => void

// DirectUpload の代わり。prepare_upload への要求の状態と、保存先へ送る途中の進み具合を再現する
const directUpload = vi.hoisted(() => ({ next: [] as ((delegate: Record<string, (xhr: unknown) => void>, done: Created) => void)[] }))

vi.mock("@rails/activestorage", () => ({
  DirectUpload: class {
    constructor(_file: File, _url: string, private delegate: Record<string, (xhr: unknown) => void>) {}
    create(done: Created) {
      directUpload.next.shift()!(this.delegate, done)
    }
  },
}))

vi.mock("./api", async (original) => ({
  ...(await original<typeof import("./api")>()),
  api: { completeUpload: vi.fn(), tree: vi.fn(async () => ({ shared_drive: null, my_drive: null })), treeChildren: vi.fn() },
}))

const stored = (delegate: Record<string, (xhr: unknown) => void>, done: Created) => {
  delegate.directUploadWillCreateBlobWithXHR({ status: 200 })
  delegate.directUploadWillStoreFileWithXHR({ upload: { addEventListener: () => {} } })
  done(null, { signed_id: "signed" })
}

const file = (name: string, size = 10) => new File(["x".repeat(size)], name)

beforeEach(() => {
  vi.mocked(api.completeUpload).mockReset()
  uploads.splice(0)
  config.max_upload_bytes = 100
})

test("送り終えたら登録し、完了にする", async () => {
  directUpload.next.push(stored)
  vi.mocked(api.completeUpload).mockResolvedValue({ id: 1, name: "報告書.txt", version: null })

  uploadFiles([file("報告書.txt")], { id: 7, label: "営業" })
  await flushPromises()

  expect(api.completeUpload).toHaveBeenCalledWith(7, "signed")
  expect(uploads.map((upload) => [upload.name, upload.status])).toEqual([["報告書.txt", "done"]])
})

test("大きすぎるファイルは、送り始める前に断る", async () => {
  uploadFiles([file("大きい.mov", 101)], { id: 7, label: "営業" })
  await flushPromises()

  expect(uploads[0]).toMatchObject({ status: "error", message: "ファイルの大きさは 100 Bytes までです" })
})

test("1段目で断られたら、サーバが返した理由を出し、次のファイルへ進む", async () => {
  directUpload.next.push((delegate, done) => {
    delegate.directUploadWillCreateBlobWithXHR({ status: 422, response: { errors: ["名前が同じフォルダの中のものと重複しています。"] } })
    done("Error creating Blob")
  })
  directUpload.next.push(stored)
  vi.mocked(api.completeUpload).mockResolvedValue({ id: 2, name: "b.txt", version: null })

  uploadFiles([file("a.txt"), file("b.txt")], { id: 7, label: "営業" })
  await flushPromises()

  expect(uploads.map((upload) => [upload.status, upload.message])).toEqual([
    ["error", "名前が同じフォルダの中のものと重複しています。"],
    ["done", null],
  ])
})

test("片付けると、終わったものだけ一覧から消える", () => {
  uploads.push(
    { id: 1, name: "a", size: 1, loaded: 1, destination: "", status: "done", message: null, saved: null },
    { id: 2, name: "b", size: 1, loaded: 0, destination: "", status: "uploading", message: null, saved: null },
  )

  clearFinished()

  expect(uploads.map((upload) => upload.name)).toEqual(["b"])
})
