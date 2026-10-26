import "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api, ValidationError } from "../api"
import type { Row } from "../rows"
import RenameDialog from "./RenameDialog.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: { rename: vi.fn(), tree: vi.fn(async () => ({ shared_drive: null, my_drive: null })), treeChildren: vi.fn() },
}))

beforeEach(() => {
  vi.mocked(api.rename).mockReset()
  HTMLDialogElement.prototype.showModal = function () {
    this.open = true
  }
  HTMLDialogElement.prototype.close = function () {
    this.open = false
  }
})

const row = (overrides: Partial<Row>): Row => ({
  id: 3, kind: "file", name: "見積書.v2.xlsx", readable: true, person: null, time: null, byteSize: 1, folderId: null, ...overrides,
})

const render = async (target: Row) => {
  const wrapper = mount(RenameDialog, { attachTo: document.body })
  await (wrapper.vm as unknown as { open: (row: Row) => Promise<void> }).open(target)
  return wrapper
}

const selection = (wrapper: Awaited<ReturnType<typeof render>>) => {
  const input = wrapper.find("input").element as HTMLInputElement
  return [input.value, input.value.slice(input.selectionStart ?? 0, input.selectionEnd ?? 0)]
}

test("ファイルは名前全体を入れ、最後の拡張子を除いた部分を選んで開く", async () => {
  expect(selection(await render(row({})))).toEqual(["見積書.v2.xlsx", "見積書.v2"])
})

test("フォルダや拡張子の無い名前は、全体を選んで開く", async () => {
  expect(selection(await render(row({ kind: "folder", name: "営業.2026" })))).toEqual(["営業.2026", "営業.2026"])
  expect(selection(await render(row({ name: ".env" })))).toEqual([".env", ".env"])
})

test("変えられない理由は、開いたまま中に出す", async () => {
  vi.mocked(api.rename).mockRejectedValue(new ValidationError(["名前が同じフォルダの中のものと重複しています。"]))
  const wrapper = await render(row({}))

  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(wrapper.find("[role=alert]").text()).toBe("名前が同じフォルダの中のものと重複しています。")
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(true)
})
