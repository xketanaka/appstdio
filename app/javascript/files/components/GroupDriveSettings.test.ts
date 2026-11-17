import "../testing"
import { enableAutoUnmount, flushPromises, mount } from "@vue/test-utils"
import { afterEach, beforeEach, expect, test, vi } from "vitest"
import { api } from "../api"
import { state } from "../store"
import GroupDriveSettings from "./GroupDriveSettings.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: {
    groupDrives: vi.fn(),
    enableGroupDrive: vi.fn(),
    disableGroupDrive: vi.fn(),
    tree: vi.fn(async () => ({ shared_drive: null, my_drive: null, group_drives: [], project_drives: [] })),
    treeChildren: vi.fn(),
  },
}))

// 開いたままのダイアログが state を見ていると、次のテストで一緒に開いて読み込んでしまう
enableAutoUnmount(afterEach)

beforeEach(() => {
  vi.mocked(api.groupDrives).mockReset().mockResolvedValue({
    groups: [
      { id: 1, name: "営業部", path: ["全社", "営業部"], enabled: true },
      { id: 2, name: "総務部", path: ["全社", "総務部"], enabled: false },
    ],
  })
  vi.mocked(api.enableGroupDrive).mockReset()
  vi.mocked(api.disableGroupDrive).mockReset()
  state.groupDriveSettingsOpen = false
  HTMLDialogElement.prototype.showModal = function () {
    this.open = true
  }
  HTMLDialogElement.prototype.close = function () {
    this.open = false
  }
})

const render = async () => {
  const wrapper = mount(GroupDriveSettings, { attachTo: document.body })
  state.groupDriveSettingsOpen = true
  await flushPromises()
  return wrapper
}

const button = (wrapper: Awaited<ReturnType<typeof render>>, label: string) =>
  wrapper.findAll("button").find((it) => it.attributes("aria-label") === label || it.text() === label)!

test("管理できるグループを並べ、使っているかを示す。上位からの道筋はマウスを載せると出る", async () => {
  const wrapper = await render()

  const rows = wrapper.findAll("li").filter((li) => li.find("span[title]").exists())
  expect(rows.map((row) => row.find("span[title]").text())).toEqual(["営業部", "総務部"])
  expect(rows[0].find("span[title]").attributes("title")).toBe("全社 / 営業部")
  expect(rows[0].text()).toContain("使用中")
  expect(button(wrapper, "総務部 のグループドライブを使う").exists()).toBe(true)
})

test("「使う」はすぐ反映し、知らせを出して読み直す", async () => {
  const wrapper = await render()

  await button(wrapper, "総務部 のグループドライブを使う").trigger("click")
  await flushPromises()

  expect(api.enableGroupDrive).toHaveBeenCalledWith(2)
  expect(state.notice?.message).toBe("「総務部」のグループドライブを使うようにしました。")
  expect(api.groupDrives).toHaveBeenCalledTimes(2)
})

test("「使わない」は、中身をゴミ箱に移すかを選んでから反映する", async () => {
  const wrapper = await render()

  await button(wrapper, "営業部 のグループドライブを使わない").trigger("click")
  expect(api.disableGroupDrive).not.toHaveBeenCalled()
  expect(wrapper.text()).toContain("ゴミ箱に移しますか？")

  await button(wrapper, "ゴミ箱に移す").trigger("click")
  await flushPromises()

  expect(api.disableGroupDrive).toHaveBeenCalledWith(1, true)
  expect(state.notice?.message).toBe("「営業部」のグループドライブを使わないようにしました。")
})

test("確認で「やめる」を押すと何もしない", async () => {
  const wrapper = await render()

  await button(wrapper, "営業部 のグループドライブを使わない").trigger("click")
  await button(wrapper, "やめる").trigger("click")

  expect(wrapper.text()).not.toContain("ゴミ箱に移しますか？")
  expect(api.disableGroupDrive).not.toHaveBeenCalled()
})
