import "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { afterEach, beforeEach, expect, test, vi } from "vitest"
import { api, ValidationError, type Sharing } from "../api"
import { state } from "../store"
import ShareDialog from "./ShareDialog.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: {
    sharing: vi.fn(),
    updateSharing: vi.fn(),
    shareCandidates: vi.fn(),
    tree: vi.fn(async () => ({ shared_drive: null, my_drive: null })),
    treeChildren: vi.fn(),
  },
}))

const everyone = { type: "group" as const, id: 1, name: "全員", everyone: true }
const accounting = { type: "group" as const, id: 2, name: "経理部", everyone: false }
const sales = { type: "group" as const, id: 3, name: "営業部", everyone: false }
const ichiro = { type: "tenant_user" as const, id: 7, name: "一郎", everyone: false }

const sharing = (): Sharing => ({
  inherited: [
    { subject: everyone, role: "viewer", from: { id: 10, label: "組織共有ドライブ" }, cancelled: false },
    { subject: accounting, role: "viewer", from: null, cancelled: true },
  ],
  own: [{ subject: sales, role: "viewer" }, { subject: ichiro, role: "editor" }],
})

beforeEach(() => {
  vi.useFakeTimers()
  vi.mocked(api.sharing).mockReset().mockResolvedValue(sharing())
  vi.mocked(api.updateSharing).mockReset().mockResolvedValue(undefined)
  vi.mocked(api.shareCandidates).mockReset()
  HTMLDialogElement.prototype.showModal = function () {
    this.open = true
  }
  HTMLDialogElement.prototype.close = function () {
    this.open = false
  }
})

afterEach(() => {
  state.sharingOf = null
  vi.useRealTimers()
})

const render = async (kind: "folder" | "file" = "folder") => {
  const wrapper = mount(ShareDialog, { attachTo: document.body })
  state.sharingOf = { id: 20, name: "営業", kind }
  await flushPromises()
  return wrapper
}

const rows = (wrapper: Awaited<ReturnType<typeof render>>, section: string) =>
  wrapper.findAll(`section[aria-labelledby=${section}] li`)

test("継承した権限を継承元と一緒に上に、このフォルダの権限を下に出す", async () => {
  const wrapper = await render()

  expect(rows(wrapper, "share-inherited").map((li) => li.text())).toEqual([
    "全員閲覧者（組織共有ドライブから継承）打ち消す",
    "経理部閲覧者（上位のフォルダから継承）打ち消しをやめる",
  ])
  expect(wrapper.find("#share-own").text()).toBe("このフォルダに設定された権限")
  expect(rows(wrapper, "share-own").map((li) => li.find("span").text())).toEqual(["営業部", "一郎"])
})

test("ファイルでは見出しを「このファイル」にする", async () => {
  const wrapper = await render("file")

  expect(wrapper.find("#share-own").text()).toBe("このファイルに設定された権限")
})

test("保存すると、開いたときからの差分だけを送る", async () => {
  vi.mocked(api.shareCandidates).mockResolvedValue({ candidates: [{ ...everyone, detail: null }, { type: "tenant_user", id: 8, name: "二郎", everyone: false, detail: "jiro@example.com" }] })
  const wrapper = await render()

  const [everyoneRow, accountingRow] = rows(wrapper, "share-inherited")
  await everyoneRow.find("button").trigger("click")
  await accountingRow.find("button").trigger("click")
  await wrapper.find("select").setValue("manager")
  await wrapper.find("[aria-label='一郎 を外す']").trigger("click")
  await wrapper.find("#share-search").setValue("じ")
  await vi.runAllTimersAsync()
  await wrapper.findAll("[aria-label=追加する相手の候補] button").find((each) => each.text().startsWith("二郎"))!.trigger("click")
  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(vi.mocked(api.updateSharing).mock.calls[0]).toEqual([20, expect.arrayContaining([
    { subject_type: "group", subject_id: 1, role: "none" },
    { subject_type: "group", subject_id: 2, role: null },
    { subject_type: "group", subject_id: 3, role: "manager" },
    { subject_type: "tenant_user", subject_id: 7, role: null },
    { subject_type: "tenant_user", subject_id: 8, role: "viewer" },
  ])])
  expect(vi.mocked(api.updateSharing).mock.calls[0][1]).toHaveLength(5)
  expect(state.notice?.message).toBe("「営業」の共有設定を保存しました")
})

test("何も変えずに保存すれば、送らずに閉じる", async () => {
  const wrapper = await render()

  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(api.updateSharing).not.toHaveBeenCalled()
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(false)
})

test("断られた理由は、開いたまま中に出す", async () => {
  vi.mocked(api.updateSharing).mockRejectedValue(new ValidationError(["管理者が1人もいなくなります。"]))
  const wrapper = await render()

  await wrapper.find("select").setValue("editor")
  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(wrapper.find("[role=alert]").text()).toBe("管理者が1人もいなくなります。")
  expect((wrapper.find("dialog").element as HTMLDialogElement).open).toBe(true)
})
