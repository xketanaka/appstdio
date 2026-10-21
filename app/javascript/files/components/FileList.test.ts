import { testRouter } from "../testing"
import { mount } from "@vue/test-utils"
import { expect, test } from "vitest"
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
