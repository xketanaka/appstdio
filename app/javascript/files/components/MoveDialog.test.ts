import "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api, NotFoundError, ValidationError, type FolderPayload } from "../api"
import MoveDialog from "./MoveDialog.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: { folder: vi.fn(), move: vi.fn(), tree: vi.fn(async () => ({ shared_drive: null, my_drive: null })), treeChildren: vi.fn() },
}))

const folder = (id: number, label: string, children: { id: number, name: string }[], overrides: Partial<FolderPayload> = {}): FolderPayload => ({
  folder: { id, label },
  section: "shared_drive",
  breadcrumbs: [],
  via_shared: false,
  can_edit: true,
  entries: children.map((child) => ({
    ...child, kind: "folder", readable: true, owner: null, updated_at: null, byte_size: null,
  })),
  ...overrides,
})

const sales = folder(2, "営業", [{ id: 3, name: "見積" }, { id: 4, name: "提案" }], { breadcrumbs: [{ id: 1, label: "組織共有ドライブ" }] })
const estimates = folder(3, "見積", [], { breadcrumbs: [{ id: 1, label: "組織共有ドライブ" }, { id: 2, label: "営業" }] })

beforeEach(() => {
  vi.mocked(api.folder).mockReset()
  vi.mocked(api.move).mockReset()
  HTMLDialogElement.prototype.showModal = function () {
    this.open = true
  }
  HTMLDialogElement.prototype.close = function () {
    this.open = false
  }
})

const render = async () => {
  vi.mocked(api.folder).mockResolvedValueOnce(sales)
  const wrapper = mount(MoveDialog, { props: { from: { id: 2, label: "営業" } }, attachTo: document.body })
  await (wrapper.vm as unknown as { open: (items: { id: number, name: string }[]) => Promise<void> }).open([{ id: 4, name: "提案" }])
  await flushPromises()
  return wrapper
}

const submit = (wrapper: Awaited<ReturnType<typeof render>>) => wrapper.findAll("button").find((button) => button.text() === "ここに移動")!

test("今いるフォルダから始め、そこへは移せない。移すフォルダの中へは入れない", async () => {
  const wrapper = await render()

  expect(wrapper.find("h2").text()).toBe("「提案」を移動")
  expect(wrapper.find("#move-location").text()).toBe("営業")
  expect(submit(wrapper).attributes("disabled")).toBeDefined()
  expect(wrapper.find("button[aria-label='提案 を開く']").attributes("disabled")).toBeDefined()
})

test("フォルダをたどって移し、閉じて知らせる", async () => {
  const wrapper = await render()
  vi.mocked(api.folder).mockResolvedValueOnce(estimates)
  vi.mocked(api.move).mockResolvedValue(undefined)

  await wrapper.find("button[aria-label='見積 を開く']").trigger("click")
  await flushPromises()
  await submit(wrapper).trigger("click")
  await flushPromises()

  expect(api.move).toHaveBeenCalledWith([4], 3)
  expect(wrapper.emitted("moved")).toHaveLength(1)
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(false)
})

test("移せない理由は、開いたまま中に出す", async () => {
  const wrapper = await render()
  vi.mocked(api.folder).mockResolvedValueOnce(estimates)
  vi.mocked(api.move).mockRejectedValue(new ValidationError(["移動先に「提案」と同じ名前のものがあります。"]))

  await wrapper.find("button[aria-label='見積 を開く']").trigger("click")
  await flushPromises()
  await submit(wrapper).trigger("click")
  await flushPromises()

  expect(wrapper.find("[role=alert]").text()).toBe("移動先に「提案」と同じ名前のものがあります。")
  expect(wrapper.emitted("moved")).toBeUndefined()
})

test("閲覧できる祖先が尽きたら、ドライブを選ぶ段に戻る", async () => {
  const wrapper = await render()
  vi.mocked(api.folder).mockResolvedValueOnce(folder(1, "組織共有ドライブ", [{ id: 2, name: "営業" }]))

  await wrapper.find("button[aria-label='ひとつ上へ']").trigger("click")
  await flushPromises()
  expect(api.folder).toHaveBeenLastCalledWith({ id: "1" })

  await wrapper.find("button[aria-label='ひとつ上へ']").trigger("click")
  await flushPromises()
  expect(wrapper.find("#move-location").text()).toBe("ドライブ")
  expect(wrapper.text()).toContain("マイドライブ")
})

test("たどった先のフォルダが見つからないときは、一覧と同じ文言で伝える", async () => {
  const wrapper = await render()
  vi.mocked(api.folder).mockRejectedValueOnce(new NotFoundError("/files/api/folders/3"))

  await wrapper.find("button[aria-label='見積 を開く']").trigger("click")
  await flushPromises()

  expect(wrapper.find("[role=alert]").text()).toBe("フォルダが見つからないか、開く権限がありません")
})
