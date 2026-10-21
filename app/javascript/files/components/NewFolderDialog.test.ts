import "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api, NotFoundError, ValidationError } from "../api"
import NewFolderDialog from "./NewFolderDialog.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: { createFolder: vi.fn() },
}))

beforeEach(() => {
  vi.mocked(api.createFolder).mockReset()
  // jsdom の dialog は showModal / close を持たないことがあるので、open 属性だけ切り替える
  HTMLDialogElement.prototype.showModal = function () {
    this.open = true
  }
  HTMLDialogElement.prototype.close = function () {
    this.open = false
  }
})

const render = async () => {
  const wrapper = mount(NewFolderDialog, { props: { parentId: 7 }, attachTo: document.body })
  await (wrapper.vm as unknown as { open: () => Promise<void> }).open()
  return wrapper
}

test("仮の名前を入れて開き、作れたら閉じて知らせる", async () => {
  vi.mocked(api.createFolder).mockResolvedValue({ id: 8, name: "企画" })
  const wrapper = await render()

  expect((wrapper.find("input").element as HTMLInputElement).value).toBe("無題のフォルダ")
  await wrapper.find("input").setValue("企画")
  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(api.createFolder).toHaveBeenCalledWith(7, "企画")
  expect(wrapper.emitted("created")).toEqual([[{ id: 8, name: "企画" }]])
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(false)
})

test("入力の誤りはダイアログを開いたまま中に出す", async () => {
  vi.mocked(api.createFolder).mockRejectedValue(new ValidationError(["名前が同じフォルダの中のものと重複しています。"]))
  const wrapper = await render()

  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(wrapper.find("[role=alert]").text()).toBe("名前が同じフォルダの中のものと重複しています。")
  expect(wrapper.find("input").attributes("aria-invalid")).toBe("true")
  expect(wrapper.emitted("created")).toBeUndefined()
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(true)
})

test("作成先が見つからないときは、時間をおいてとは言わずにそう伝える", async () => {
  vi.mocked(api.createFolder).mockRejectedValue(new NotFoundError("/files/api/folders"))
  const wrapper = await render()

  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(wrapper.find("[role=alert]").text()).toBe("作成先のフォルダが見つからないか、開く権限がありません")
})
