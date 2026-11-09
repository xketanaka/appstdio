import "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test, vi } from "vitest"
import { api, type Activity } from "../api"
import ActivityList from "./ActivityList.vue"

vi.mock("../api", async (original) => ({
  ...(await original<typeof import("../api")>()),
  api: { activities: vi.fn() },
}))

beforeEach(() => {
  vi.mocked(api.activities).mockReset()
})

const activity = (overrides: object) => ({
  id: 1, action: "created", actor: "佐藤さん", created_at: "2026-11-09T14:20:00+09:00",
  node: { id: 3, kind: "file", name: "見積書.xlsx" }, location: [], detail: {}, ...overrides,
}) as Activity

const render = async () => {
  const wrapper = mount(ActivityList, { props: { nodeId: 2 } })
  await flushPromises()
  return wrapper
}

test("操作ごとの文と、だれがいつ行ったかを並べ、配下のものには場所を添える", async () => {
  vi.mocked(api.activities).mockResolvedValue({
    activities: [
      activity({ id: 4, action: "moved", detail: { from: null, to: "営業" }, location: ["見積", null] }),
      activity({ id: 3, action: "updated", detail: { version: 3, restored_from: 1 } }),
      activity({ id: 2, action: "renamed", detail: { from: "見積.xlsx", to: "見積書.xlsx" } }),
      activity({ id: 1, action: "purged", actor: null }),
    ],
    next_before: null,
  })
  const items = (await render()).findAll("li").map((li) => li.findAll("p").map((p) => p.text()))

  expect(items).toEqual([
    ["「見積書.xlsx」を「（閲覧できないフォルダ）」から「営業」に移動しました", "場所: 見積 / （閲覧できないフォルダ）", "佐藤さん・2026/11/09 14:20"],
    ["「見積書.xlsx」を版1の中身に戻し、版3を作りました", "佐藤さん・2026/11/09 14:20"],
    ["「見積.xlsx」から「見積書.xlsx」に名前を変更しました", "佐藤さん・2026/11/09 14:20"],
    ["「見積書.xlsx」を完全に削除しました", "自動処理・2026/11/09 14:20"],
  ])
})

test("続きがあれば「さらに読み込む」で、前回の最後より古い分を足す", async () => {
  vi.mocked(api.activities)
    .mockResolvedValueOnce({ activities: [activity({ id: 9 })], next_before: 9 })
    .mockResolvedValueOnce({ activities: [activity({ id: 5, action: "deleted" })], next_before: null })
  const wrapper = await render()

  await wrapper.find("button").trigger("click")
  await flushPromises()

  expect(api.activities).toHaveBeenLastCalledWith(2, 9)
  expect(wrapper.findAll("li")).toHaveLength(2)
  expect(wrapper.find("button").exists()).toBe(false)
})

test("1件も無ければ、無いことを示す", async () => {
  vi.mocked(api.activities).mockResolvedValue({ activities: [], next_before: null })

  expect((await render()).text()).toBe("操作履歴はありません")
})
