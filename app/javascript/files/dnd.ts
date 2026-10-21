import { ref } from "vue"
import { ForbiddenError, ValidationError } from "./api"
import { t } from "./i18n"
import { moveItems, notify } from "./store"

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
    await moveItems(current.items, destination)
  } catch (error) {
    if (error instanceof ValidationError) notify(error.messages.join(" "), { error: true })
    else if (error instanceof ForbiddenError) notify(t("move.forbidden"), { error: true })
    else {
      notify(t("move.failed"), { error: true })
      console.error(error)
    }
  }
}

// 落とし先にする要素へ v-on で付ける。over は、今その上にあるかを id で持つ（見た目に使う）
export function useDropTargets() {
  const over = ref<number | null>(null)

  const handlers = (destination: { id: number, label: string }) => ({
    dragover: (event: DragEvent) => {
      if (!canDropOn(destination.id) || !event.dataTransfer?.types.includes(TYPE)) return
      event.preventDefault()
      event.dataTransfer.dropEffect = "move"
      over.value = destination.id
    },
    dragleave: (event: DragEvent) => {
      // 子の要素へ入っただけのときは、まだ上にいる
      if (!(event.currentTarget as Node).contains(event.relatedTarget as Node | null)) over.value = null
    },
    drop: (event: DragEvent) => {
      event.preventDefault()
      over.value = null
      dropOn(destination)
    },
  })

  return { over, handlers }
}
