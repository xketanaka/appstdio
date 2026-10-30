import "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api, NotFoundError } from "../api"
import type { Row } from "../rows"
import { state } from "../store"
import PurgeDialog from "./PurgeDialog.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: { purgeNodes: vi.fn(), tree: vi.fn(async () => ({ shared_drive: null, my_drive: null })), treeChildren: vi.fn() },
}))

beforeEach(() => {
  vi.mocked(api.purgeNodes).mockReset()
  HTMLDialogElement.prototype.showModal = function () {
    this.open = true
  }
  HTMLDialogElement.prototype.close = function () {
    this.open = false
  }
})

const row = (overrides: Partial<Row>): Row => ({
  id: 3, kind: "file", name: "古い見積.xlsx", readable: true, editable: true, manageable: false, person: null, time: null, byteSize: 1, folderId: null, ...overrides,
})

const render = async (rows: Row[]) => {
  const wrapper = mount(PurgeDialog, { attachTo: document.body })
  ;(wrapper.vm as unknown as { open: (rows: Row[]) => void }).open(rows)
  await flushPromises()
  return wrapper
}

test("消すものと、取り消せないことを示し、確かめてから消す", async () => {
  const wrapper = await render([row({})])

  expect(wrapper.find("#purge-message").text()).toBe("「古い見積.xlsx」を完全に削除します。この操作は取り消せません。")
  expect(api.purgeNodes).not.toHaveBeenCalled()

  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(api.purgeNodes).toHaveBeenCalledWith([3])
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(false)
  expect(state.notice?.message).toBe("「古い見積.xlsx」を完全に削除しました")
})

test("フォルダを含むときは、中のものも消えることを添える", async () => {
  const wrapper = await render([row({}), row({ id: 4, kind: "folder", name: "営業" })])

  expect(wrapper.find("#purge-message").text()).toBe(
    "2件を完全に削除します。この操作は取り消せません。 フォルダの中のものもすべて削除されます。",
  )
})

test("消せない理由は、開いたまま中に出す", async () => {
  vi.mocked(api.purgeNodes).mockRejectedValue(new NotFoundError())
  const wrapper = await render([row({})])

  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(wrapper.find("[role=alert]").text()).toBe("削除するものが見つからないか、ゴミ箱から消えています")
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(true)
})
