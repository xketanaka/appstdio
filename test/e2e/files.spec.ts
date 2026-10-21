import { expect, test } from "@playwright/test"
import { login, scenario, type User } from "./support"

// 利用者の主な流れを、実際の操作で端から端まで動かす。権限の組み合わせや入力の誤りは
// 結合テスト（test/integration）と Vitest で確かめているので、ここでは網羅しない

type FilesScenario = { owner: User, member: User, folders: { sales: number, estimates: number, hr: number } }

// ファイルの中のテストは1つのワーカーで順に流れ、このデータを共有する。
// 他のテストの結果に左右されないよう、データを変えるテストは他のテストが見るものに触れないこと
let data: FilesScenario

test.beforeAll(() => {
  data = scenario<FilesScenario>("files")
})

test("ブックマークしたフォルダを開き、パンくずと左ペインでドライブを行き来する", async ({ page }) => {
  await login(page, data.owner)
  await page.goto(`/files/folders/${data.folders.estimates}`)
  await expect(page.getByRole("heading", { name: "見積" })).toBeVisible()
  await expect(page).toHaveTitle(/見積$/)
  // 左ペインは、開いているフォルダまでの祖先を開いてそのフォルダを示す
  const sidePane = page.locator("#side-pane")
  await expect(sidePane.getByRole("link", { name: "見積" })).toHaveAttribute("aria-current", "page")

  // ここから先はページを読み直さずに移る
  await page.evaluate(() => Object.assign(window, { notReloaded: true }))
  await sidePane.locator("summary", { hasText: "マイドライブ" }).locator("svg").click()

  await page.getByRole("navigation", { name: "現在の場所" }).getByRole("link", { name: "営業" }).click()
  await expect(page.getByRole("heading", { name: "営業" })).toBeVisible()
  await expect(sidePane.getByRole("link", { name: "営業" })).toHaveAttribute("aria-current", "page")
  await page.getByRole("navigation", { name: "現在の場所" }).getByRole("link", { name: "組織共有ドライブ" }).click()
  await expect(page.getByRole("heading", { name: "組織共有ドライブ" })).toBeVisible()

  await sidePane.getByRole("link", { name: "マイドライブ" }).click()
  await expect(page.getByRole("heading", { name: "マイドライブ" })).toBeVisible()
  await page.goBack()
  await expect(page.getByRole("heading", { name: "組織共有ドライブ" })).toBeVisible()

  expect(await page.evaluate(() => "notReloaded" in window)).toBe(true)
  await expect(sidePane.locator("details[open]")).toHaveCount(2)
  await expect(sidePane.getByRole("link", { name: "組織共有ドライブ" })).toHaveAttribute("aria-current", "page")
})

test("フォルダを作ると、一覧と左ペインに出る", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files/my_drive")
  await expect(page.getByRole("heading", { name: "マイドライブ" })).toBeVisible()

  await page.locator("summary", { hasText: "作成" }).click()
  await page.getByRole("button", { name: "フォルダ" }).click()
  const dialog = page.getByRole("dialog", { name: "新しいフォルダ" })
  await dialog.getByLabel("フォルダの名前").fill("企画")
  await dialog.getByRole("button", { name: "作成" }).click()

  await expect(dialog).toBeHidden()
  await expect(page.locator("#file-list").getByRole("row", { name: /企画/ })).toBeVisible()
  await expect(page.locator("#side-pane").getByRole("link", { name: "企画" })).toBeVisible()
})

test("特権モードにすると権限の無いフォルダも開け、終えるとドライブのルートに戻る", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files")
  const list = page.locator("#file-list")
  await expect(list.getByTitle("権限がないため開けません")).toHaveText("人事")

  // 移動などの知らせも status なので、特権モードの帯は文言で絞る
  const banner = page.getByRole("status").filter({ hasText: "特権モードです" })
  await page.locator("#side-pane").getByRole("switch", { name: "特権モード" }).click()
  await expect(banner).toBeVisible()
  await expect(list.getByTitle("権限がないため開けません")).toHaveCount(0)
  await list.getByRole("row", { name: /人事/ }).dblclick()
  await expect(page.getByRole("heading", { name: "人事" })).toBeVisible()

  await banner.getByRole("button", { name: "特権モードを終える" }).click()
  await expect(banner).toBeHidden()
  await expect(page).toHaveURL("/files")
  await expect(list.getByTitle("権限がないため開けません")).toHaveText("人事")
})

test("複数を選んで、別のフォルダへまとめて移す", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files/my_drive")
  const list = page.locator("#file-list")

  await list.getByRole("row", { name: /下書き/ }).click()
  await list.getByRole("row", { name: /メモ\.txt/ }).click({ modifiers: ["ControlOrMeta"] })
  const toolbar = page.getByRole("toolbar")
  await expect(toolbar).toContainText("2件を選択中")
  await toolbar.getByRole("button", { name: "移動" }).click()

  const dialog = page.getByRole("dialog", { name: "2件を移動" })
  await dialog.getByRole("button", { name: "保管 を開く" }).click()
  await expect(dialog.locator("#move-location")).toHaveText("保管")
  await dialog.getByRole("button", { name: "ここに移動" }).click()

  await expect(dialog).toBeHidden()
  await expect(list.getByRole("row", { name: /下書き|メモ\.txt/ })).toHaveCount(0)
  await list.getByRole("row", { name: /保管/ }).dblclick()
  await expect(page.getByRole("heading", { name: "保管" })).toBeVisible()
  await expect(list.getByRole("row", { name: /下書き|メモ\.txt/ })).toHaveCount(2)
})

test("ドラッグして、一覧のフォルダや左ペインのドライブへ移す", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files/my_drive")
  const list = page.locator("#file-list")
  const notice = page.getByRole("status").filter({ hasText: "移動しました" })

  await list.getByRole("row", { name: /議事録\.txt/ }).dragTo(list.getByRole("row", { name: /資料/ }))
  await expect(notice).toHaveText("「議事録.txt」を「資料」に移動しました")
  await expect(list.getByRole("row", { name: /議事録\.txt/ })).toHaveCount(0)

  await list.getByRole("row", { name: /資料/ }).dblclick()
  await expect(page.getByRole("heading", { name: "資料" })).toBeVisible()
  await list.getByRole("row", { name: /議事録\.txt/ }).dragTo(page.locator("#side-pane summary", { hasText: "マイドライブ" }))
  await expect(notice).toHaveText("「議事録.txt」を「マイドライブ」に移動しました")
  await expect(list.getByRole("row", { name: /議事録\.txt/ })).toHaveCount(0)
})
