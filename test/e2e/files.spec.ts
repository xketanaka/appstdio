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

  // ここから先はページを読み直さずに移る
  await page.evaluate(() => Object.assign(window, { notReloaded: true }))
  const sidePane = page.locator("#side-pane")
  await sidePane.locator("summary", { hasText: "マイドライブ" }).locator("svg").click()

  await page.getByRole("navigation", { name: "現在の場所" }).getByRole("link", { name: "営業" }).click()
  await expect(page.getByRole("heading", { name: "営業" })).toBeVisible()
  await page.getByRole("navigation", { name: "現在の場所" }).getByRole("link", { name: "組織共有ドライブ" }).click()
  await expect(page.getByRole("heading", { name: "組織共有ドライブ" })).toBeVisible()

  await sidePane.getByRole("link", { name: "マイドライブ" }).click()
  await expect(page.getByRole("heading", { name: "マイドライブ" })).toBeVisible()
  await page.goBack()
  await expect(page.getByRole("heading", { name: "組織共有ドライブ" })).toBeVisible()

  expect(await page.evaluate(() => "notReloaded" in window)).toBe(true)
  await expect(sidePane.locator("details[open]")).toHaveCount(2)
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
  await expect(page.locator("#file-list").getByRole("link", { name: "企画" })).toBeVisible()
  await expect(page.locator("#side-pane").getByRole("link", { name: "企画" })).toBeVisible()
})

test("特権モードにすると権限の無いフォルダも開け、終えるとドライブのルートに戻る", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files")
  const list = page.locator("#file-list")
  await expect(list.getByText("人事")).toBeVisible()
  await expect(list.getByRole("link", { name: "人事" })).toHaveCount(0)

  await page.locator("#side-pane").getByRole("switch", { name: "特権モード" }).click()
  await expect(page.getByRole("status")).toContainText("特権モードです")
  await list.getByRole("link", { name: "人事" }).click()
  await expect(page.getByRole("heading", { name: "人事" })).toBeVisible()

  await page.getByRole("status").getByRole("button", { name: "特権モードを終える" }).click()
  await expect(page.getByRole("status")).toBeHidden()
  await expect(page).toHaveURL("/files")
  await expect(list.getByRole("link", { name: "人事" })).toHaveCount(0)
})
