import { testRouter } from "../testing"
import { mount } from "@vue/test-utils"
import { describe, expect, test } from "vitest"
import type { Row } from "../rows"
import FileList from "./FileList.vue"

const row = (overrides: Partial<Row>): Row => ({
  id: 1, kind: "file", name: "議事録.docx", readable: true,
  person: "管理者", time: "2026-10-05T19:20:00+09:00", byteSize: 25_088, folderId: null,
  ...overrides,
})

const render = async (rows: Row[], trash = false) => {
  const router = testRouter()
  await router.push("/shared_drive")
  return mount(FileList, { props: { rows, empty: "何もありません", trash }, global: { plugins: [router] } })
}

test("閲覧できる項目は付帯情報を出し、フォルダはリンクにする", async () => {
  const wrapper = await render([row({ id: 2, kind: "folder", name: "営業", byteSize: null, folderId: 2 }), row({})])
  const cells = wrapper.findAll("tbody tr")[1].findAll("td")

  expect(wrapper.find("tbody a").attributes("href")).toBe("/folders/2")
  expect(cells[1].text()).toBe("管理者")
  expect(cells[3].text()).toBe("24.5 KB")
})

test("閲覧できない項目は名前だけを薄く出し、開けない", async () => {
  const wrapper = await render([row({ kind: "folder", readable: false, person: null, time: null, byteSize: null })])
  const cells = wrapper.findAll("tbody td")

  expect(wrapper.find("tbody a").exists()).toBe(false)
  expect(cells[0].find("[title]").attributes("title")).toBe("権限がないため開けません")
  expect(cells.slice(1, 4).map((cell) => cell.text())).toEqual(["", "", ""])
})

test("ゴミ箱では列の見出しと操作が変わる", async () => {
  const wrapper = await render([row({})], true)

  expect(wrapper.findAll("th").map((th) => th.text())).toContain("削除した人")
  expect(wrapper.find("details").text()).toContain("元に戻す")
})

test("無ければその旨を出す", async () => {
  const wrapper = await render([])

  expect(wrapper.find("#file-list + p").text()).toBe("何もありません")
})

describe("選べる一覧", () => {
  const renderSelectable = async (selected: number[] = [], slots = {}) => {
    const router = testRouter()
    await router.push("/shared_drive")
    return mount(FileList, {
      props: {
        rows: [row({ id: 2, kind: "folder", name: "営業", byteSize: null, folderId: 2 }), row({})],
        empty: "",
        selectable: true,
        selected: new Set(selected),
        canMove: true,
      },
      slots,
      global: { plugins: [router] },
    })
  }

  test("クリックで選び、修飾キーを伝える。名前はリンクにしない", async () => {
    const wrapper = await renderSelectable()
    const rows = wrapper.findAll("tbody tr")

    await rows[0].trigger("click")
    await rows[1].trigger("click", { ctrlKey: true })
    await rows[1].trigger("click", { shiftKey: true })

    expect(wrapper.emitted("select")).toEqual([
      [2, { toggle: false, range: false }],
      [1, { toggle: true, range: false }],
      [1, { toggle: false, range: true }],
    ])
    expect(wrapper.find("tbody a").exists()).toBe(false)
  })

  test("ダブルクリックと Enter で開く", async () => {
    const wrapper = await renderSelectable()
    const folder = wrapper.findAll("tbody tr")[0]

    await folder.trigger("dblclick")
    await folder.trigger("keydown", { key: "Enter" })

    expect(wrapper.emitted<[Row]>("open")?.map(([opened]) => opened.id)).toEqual([2, 2])
  })

  test("選んだ行を示し、選択中は見出しの行を操作の帯に差し替える", async () => {
    const wrapper = await renderSelectable([1], { toolbar: "<div role='toolbar'>1件を選択中</div>" })

    expect(wrapper.findAll("tbody tr").map((tr) => tr.attributes("aria-selected"))).toEqual(["false", "true"])
    expect(wrapper.find("thead [role=toolbar]").text()).toBe("1件を選択中")
    expect(wrapper.find("thead").text()).not.toContain("オーナー")
  })

  test("行のメニューの「移動」で、その行を知らせる。行の選択には響かない", async () => {
    const wrapper = await renderSelectable()

    await wrapper.findAll("tbody tr")[1].find("details button").trigger("click")

    expect(wrapper.emitted<[Row]>("move")?.[0][0].id).toBe(1)
    expect(wrapper.emitted("select")).toBeUndefined()
  })
})
