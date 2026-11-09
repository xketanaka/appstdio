import "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api } from "../api"
import { state } from "../store"
import HistoryPanel from "./HistoryPanel.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: {
    activities: vi.fn(async () => ({ activities: [], next_before: null })),
    versions: vi.fn(async () => ({ can_edit: false, versions: [] })),
  },
}))

beforeEach(() => {
  HTMLDialogElement.prototype.showModal = function () {
    this.open = true
  }
  state.historyOf = null
})

const open = async (kind: "folder" | "file") => {
  const wrapper = mount(HistoryPanel)
  state.historyOf = { id: 3, name: "見積書.xlsx", kind }
  await flushPromises()
  return wrapper
}

test("ファイルは操作履歴のタブで開き、版のタブに切り替えられる", async () => {
  const wrapper = await open("file")

  expect(wrapper.findAll("[role=tab]").map((tab) => [tab.text(), tab.attributes("aria-selected")]))
    .toEqual([["操作履歴", "true"], ["版", "false"]])
  expect(api.activities).toHaveBeenCalledWith(3, undefined)

  await wrapper.findAll("[role=tab]")[1].trigger("click")
  await flushPromises()
  expect(api.versions).toHaveBeenCalledWith(3)
})

test("フォルダには版が無いので、タブを出さない", async () => {
  const wrapper = await open("folder")

  expect(wrapper.find("[role=tablist]").exists()).toBe(false)
  expect(wrapper.find("h2").text()).toBe("「見積書.xlsx」の履歴")
})
