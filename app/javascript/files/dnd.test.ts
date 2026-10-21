import "./testing"
import { flushPromises } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api, NotFoundError, ValidationError } from "./api"
import { canDropOn, endDrag, startDrag, useDropTargets } from "./dnd"
import { state } from "./store"

vi.mock("./api", async (original) => ({
  ...(await original<typeof import("./api")>()),
  api: { move: vi.fn(), tree: vi.fn(async () => ({ shared_drive: null, my_drive: null })), treeChildren: vi.fn() },
}))

const TYPE = "application/x-appstdio-nodes"

// jsdom には DataTransfer が無いので、使う分だけ用意する
const dragEvent = (type: string) => {
  const data = new Map<string, string>()
  const event = new Event(type, { cancelable: true }) as DragEvent
  Object.defineProperty(event, "dataTransfer", {
    value: {
      types: [TYPE], effectAllowed: "", dropEffect: "",
      setData: (key: string, value: string) => data.set(key, value), setDragImage: () => {},
    },
  })
  return event
}

beforeEach(() => {
  vi.mocked(api.move).mockReset()
  state.notice = null
  endDrag()
})

test("自分自身・ドラッグしているもの・今いる場所へは落とせない", () => {
  startDrag(dragEvent("dragstart"), [{ id: 4, name: "提案" }], 2)

  expect(canDropOn(4)).toBe(false)
  expect(canDropOn(2)).toBe(false)
  expect(canDropOn(3)).toBe(true)
  endDrag()
  expect(canDropOn(3)).toBe(false)
})

test("落としたら移し、知らせる", async () => {
  vi.mocked(api.move).mockResolvedValue(undefined)
  const { handlers } = useDropTargets()
  startDrag(dragEvent("dragstart"), [{ id: 4, name: "提案" }, { id: 5, name: "議事録" }], 2)

  const over = dragEvent("dragover")
  handlers({ id: 3, label: "見積" }).dragover(over)
  handlers({ id: 3, label: "見積" }).drop(dragEvent("drop"))
  await flushPromises()

  expect(over.defaultPrevented).toBe(true)
  expect(api.move).toHaveBeenCalledWith([4, 5], 3)
  expect(state.notice?.message).toBe("2件を「見積」に移動しました")
  expect(state.notice?.error).toBe(false)
})

test("知らせの「元に戻す」で、元のフォルダへ移し直す", async () => {
  vi.mocked(api.move).mockResolvedValue(undefined)
  const { handlers } = useDropTargets()
  startDrag(dragEvent("dragstart"), [{ id: 4, name: "提案" }], 2)
  handlers({ id: 3, label: "見積" }).drop(dragEvent("drop"))
  await flushPromises()

  expect(state.notice?.action?.label).toBe("元に戻す")
  state.notice?.action?.run()
  await flushPromises()

  expect(api.move).toHaveBeenLastCalledWith([4], 2)
  expect(state.notice).toMatchObject({ message: "移動を元に戻しました", error: false })
  expect(state.notice?.action).toBeUndefined()
})

test("落とせない場所の上では、落とせる印（preventDefault）を出さない", () => {
  const { handlers, over } = useDropTargets()
  startDrag(dragEvent("dragstart"), [{ id: 4, name: "提案" }], 2)

  const event = dragEvent("dragover")
  handlers({ id: 4, label: "提案" }).dragover(event)

  expect(event.defaultPrevented).toBe(false)
  expect(over.value).toBeNull()
})

test("移せなければ、理由を知らせる", async () => {
  vi.mocked(api.move).mockRejectedValue(new ValidationError(["移動先に「提案」と同じ名前のものがあります。"]))
  const { handlers } = useDropTargets()
  startDrag(dragEvent("dragstart"), [{ id: 4, name: "提案" }], 2)

  handlers({ id: 3, label: "見積" }).drop(dragEvent("drop"))
  await flushPromises()

  expect(state.notice).toEqual({ message: "移動先に「提案」と同じ名前のものがあります。", error: true })
})

test("元に戻す先が見つからないときは、元に戻せなかったと伝える", async () => {
  vi.mocked(api.move).mockResolvedValueOnce(undefined).mockRejectedValueOnce(new NotFoundError("/files/api/nodes/move"))
  const { handlers } = useDropTargets()
  startDrag(dragEvent("dragstart"), [{ id: 4, name: "提案" }], 2)
  handlers({ id: 3, label: "見積" }).drop(dragEvent("drop"))
  await flushPromises()

  state.notice?.action?.run()
  await flushPromises()

  expect(state.notice).toMatchObject({
    message: "元の場所が見つからないか、開く権限がなくなったため、元に戻せませんでした", error: true,
  })
})
