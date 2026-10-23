import { ref } from "vue"
import { t } from "./i18n"
import { moveItems, notifyMoveError } from "./store"
import { uploadFiles } from "./uploads"

type Item = { id: number, name: string }

// ドラッグ中のもの。dragover の間は dataTransfer の中身を読めないので、ここに持っておく
const dragging = ref<{ items: Item[], from: number } | null>(null)

// 他のアプリから持ち込まれたもの（ファイルなど）と見分けるための種類
const TYPE = "application/x-appstdio-nodes"

export function startDrag(event: DragEvent, items: Item[], from: number) {
  dragging.value = { items, from }
  if (!event.dataTransfer) return

  event.dataTransfer.effectAllowed = "move"
  event.dataTransfer.setData(TYPE, JSON.stringify(items.map((item) => item.id)))

  // 何件を動かしているかが分かる小さな札を、カーソルに付ける
  const label = document.createElement("div")
  label.textContent = items.length === 1 ? items[0].name : t("move.dragging", { count: items.length })
  label.className = "fixed -top-96 rounded-full bg-primary-600 px-3 py-1 text-sm text-white"
  document.body.append(label)
  event.dataTransfer.setDragImage(label, -8, -8)
  setTimeout(() => label.remove())
}

export function endDrag() {
  dragging.value = null
}

// 自分自身・ドラッグしているものの中・今いる場所へは落とせない（今いる場所へは動かしても何も起きない）。
// 祖先かどうかや編集権限はここでは分からないので、落としたあとにサーバが判定する
export function canDropOn(id: number) {
  const current = dragging.value
  return current !== null && id !== current.from && !current.items.some((item) => item.id === id)
}

async function dropOn(destination: { id: number, label: string }) {
  const current = dragging.value
  endDrag()
  if (current === null) return

  try {
    await moveItems(current.items, destination, current.from)
  } catch (error) {
    notifyMoveError(error)
  }
}

// パソコンから持ち込まれたファイルか。ファイルを持ち込むと、種類に "Files" が入る
const carriesFiles = (event: DragEvent) => dragging.value === null && !!event.dataTransfer?.types.includes("Files")

// 落とし先にする要素へ v-on で付ける。over は、今その上にあるかを id で持つ（見た目に使う）。
// 画面の中のものを落とせば移動、パソコンのファイルを落とせばそのフォルダへアップロードする。
// 入れ子の落とし先（一覧の中のフォルダの行と、一覧全体）では、内側が受けたら外側へは伝えない
export function useDropTargets() {
  const over = ref<number | null>(null)

  const handlers = (destination: { id: number, label: string }) => ({
    dragover: (event: DragEvent) => {
      const moving = canDropOn(destination.id) && !!event.dataTransfer?.types.includes(TYPE)
      if (!moving && !carriesFiles(event)) return
      event.preventDefault()
      event.stopPropagation()
      if (event.dataTransfer) event.dataTransfer.dropEffect = moving ? "move" : "copy"
      over.value = destination.id
    },
    dragleave: (event: DragEvent) => {
      // 子の要素へ入っただけのときは、まだ上にいる
      if (!(event.currentTarget as Node).contains(event.relatedTarget as Node | null)) over.value = null
    },
    drop: (event: DragEvent) => {
      event.preventDefault()
      event.stopPropagation()
      over.value = null
      const files = [...(event.dataTransfer?.files ?? [])]
      if (dragging.value === null && files.length > 0) uploadFiles(files, destination)
      else dropOn(destination)
    },
  })

  return { over, handlers }
}
