import { testRouter } from "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { nextTick } from "vue"
import { api, type FolderPayload } from "../api"
import { showFolder, showSection, state } from "../store"
import FileTree from "./FileTree.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: { treeChildren: vi.fn() },
}))

const folder = (id: number, name: string, overrides = {}) => ({ id, name, readable: true, has_children: false, ...overrides })

beforeEach(() => {
  vi.mocked(api.treeChildren).mockReset()
  state.openSections.clear()
  state.openFolders.clear()
  state.children.clear()
  state.tree = {
    shared_drive: { id: 1, folders: [folder(2, "営業", { has_children: true }), folder(3, "人事", { readable: false })] },
    my_drive: { id: 9, folders: [folder(10, "下書き")] },
  }
  state.children.set(1, state.tree.shared_drive!.folders)
  state.children.set(9, state.tree.my_drive!.folders)
})

const render = async () => {
  const router = testRouter()
  await router.push("/shared_drive")
  return mount(FileTree, { global: { plugins: [router] }, attachTo: document.body })
}

const payload = (overrides: Partial<FolderPayload>): FolderPayload => ({
  folder: { id: 4, label: "見積" },
  section: "shared_drive",
  breadcrumbs: [{ id: 1, label: "組織共有ドライブ" }, { id: 2, label: "営業" }],
  via_shared: false,
  can_edit: false,
  entries: [],
  ...overrides,
})

test("開いている区分を示し、開けないフォルダはリンクにせず、子の無いフォルダに ▸ を出さない", async () => {
  showSection("shared_drive", "組織共有ドライブ")
  const wrapper = await render()

  expect(wrapper.find("[aria-current=page]").text()).toBe("組織共有ドライブ")
  expect(wrapper.findAll("details")[0].element.open).toBe(true)
  expect(wrapper.find("a[href='/folders/2']").exists()).toBe(true)
  expect(wrapper.find("a[href='/folders/3']").exists()).toBe(false)
  expect(wrapper.findAll("button[aria-expanded]").map((button) => button.attributes("aria-label"))).toEqual(["営業 の中を表示"])
})

test("▸ を押すと、その時に子のフォルダを読み込んで出す", async () => {
  showSection("shared_drive", "組織共有ドライブ")
  vi.mocked(api.treeChildren).mockResolvedValue({ 2: [folder(4, "見積")] })
  const wrapper = await render()

  await wrapper.find("button[aria-label='営業 の中を表示']").trigger("click")
  await flushPromises()

  expect(api.treeChildren).toHaveBeenCalledWith([2])
  expect(wrapper.find("a[href='/folders/4']").text()).toBe("見積")
  expect(wrapper.find("button[aria-expanded]").attributes("aria-expanded")).toBe("true")
})

test("フォルダを開くと、そこまでの祖先を開き、区分ではなくそのフォルダを選択中にする", async () => {
  vi.mocked(api.treeChildren).mockResolvedValue({ 2: [folder(4, "見積")] })
  const wrapper = await render()

  await showFolder(payload({}))
  await flushPromises()

  expect(wrapper.find("[aria-current=page]").text()).toBe("見積")
})

test("祖先をたどれないフォルダは「共有されたアイテム」を選択中にする", async () => {
  const wrapper = await render()

  await showFolder(payload({ breadcrumbs: [], via_shared: true }))
  await nextTick()

  expect(wrapper.find("[aria-current=page]").text()).toBe("共有されたアイテム")
  expect(api.treeChildren).not.toHaveBeenCalled()
})

test("利用者が開いた区分は、別の区分へ移っても閉じない", async () => {
  showSection("shared_drive", "組織共有ドライブ")
  const wrapper = await render()
  const myDrive = wrapper.findAll("details")[1].element

  myDrive.open = true
  myDrive.dispatchEvent(new Event("toggle"))
  showSection("trash", "ゴミ箱")
  await nextTick()

  expect(wrapper.findAll("details").map((details) => details.element.open)).toEqual([true, true])
  expect(wrapper.find("[aria-current=page]").text()).toBe("ゴミ箱")
})
