import { expect, test } from "vitest"
import { entryRow, trashRow } from "./rows"

const entry = {
  id: 1, kind: "folder" as const, name: "営業", readable: true,
  owner: "管理者", updated_at: "2026-10-05T19:20:00+09:00", byte_size: null,
}

test("開けるフォルダだけリンク先を持つ", () => {
  expect(entryRow(entry).folderId).toBe(1)
  expect(entryRow({ ...entry, readable: false }).folderId).toBeNull()
  expect(entryRow({ ...entry, kind: "file" }).folderId).toBeNull()
})

test("ゴミ箱の行は開けないが、付帯情報は出す", () => {
  const row = trashRow({
    id: 2, kind: "folder", name: "古い", deleted_by: "一般", deleted_at: "2026-10-06T10:00:00+09:00", byte_size: null,
  })

  expect(row.folderId).toBeNull()
  expect(row.readable).toBe(true)
  expect(row.person).toBe("一般")
})
