import type { Entry, TrashEntry } from "./api"

// 一覧の1行。フォルダ・共有されたアイテム・ゴミ箱で列の中身が違うのを、ここで揃える
export type Row = {
  id: number
  kind: "folder" | "file"
  name: string
  readable: boolean
  person: string | null
  time: string | null
  byteSize: number | null
  folderId: number | null
}

export function entryRow(entry: Entry): Row {
  return {
    id: entry.id,
    kind: entry.kind,
    name: entry.name,
    readable: entry.readable,
    person: entry.owner,
    time: entry.updated_at,
    byteSize: entry.byte_size,
    folderId: entry.kind === "folder" && entry.readable ? entry.id : null,
  }
}

// ゴミ箱の中は開けないので、フォルダでもリンクにしない
export function trashRow(entry: TrashEntry): Row {
  return {
    id: entry.id,
    kind: entry.kind,
    name: entry.name,
    readable: true,
    person: entry.deleted_by,
    time: entry.deleted_at,
    byteSize: entry.byte_size,
    folderId: null,
  }
}
