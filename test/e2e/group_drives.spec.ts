import { expect, test } from "@playwright/test"
import { login, scenario, type User } from "./support"

let data: { sato: User, tanaka: User }

test.beforeAll(() => {
  data = scenario<typeof data>("group_drives")
})

test("グループ管理者が左ペインの「⋮」からグループドライブを使うようにすると、メンバーが中にフォルダを作れる", async ({ page, browser }) => {
  const leader = await browser.newPage()
  await login(leader, data.sato)
  await leader.goto("/files")
  const leaderPane = leader.locator("#side-pane")
  await leaderPane.getByLabel("グループドライブの操作").click()
  await leaderPane.getByRole("button", { name: "使うグループを選ぶ" }).click()
  const settings = leader.getByRole("dialog", { name: "グループドライブの設定" })
  await settings.getByRole("button", { name: "営業部 のグループドライブを使う" }).click()
  await expect(settings.getByText("使用中")).toBeVisible()
  await settings.getByRole("button", { name: "閉じる" }).click()
  await leaderPane.locator("summary", { hasText: "グループドライブ" }).click()
  await expect(leaderPane.getByRole("link", { name: "営業部" })).toBeVisible()
  await leader.close()

  await login(page, data.tanaka)
  await page.goto("/files")
  const sidePane = page.locator("#side-pane")
  await expect(sidePane.getByLabel("グループドライブの操作")).toHaveCount(0)
  await sidePane.locator("summary", { hasText: "グループドライブ" }).click()
  await sidePane.getByRole("link", { name: "営業部" }).click()
  await expect(page.getByRole("heading", { name: "営業部" })).toBeVisible()
  await expect(sidePane.getByRole("link", { name: "営業部" })).toHaveAttribute("aria-current", "page")

  await page.locator("summary", { hasText: "作成" }).click()
  await page.getByRole("button", { name: "フォルダ" }).click()
  const dialog = page.getByRole("dialog", { name: "新しいフォルダ" })
  await dialog.getByLabel("フォルダの名前").fill("見積")
  await dialog.getByRole("button", { name: "作成" }).click()
  await expect(page.locator("#file-list").getByRole("row", { name: /見積/ })).toBeVisible()
  // メンバーは編集者なので、ドライブの共有設定は変えられない
  await expect(page.getByRole("button", { name: "共有" })).toHaveCount(0)
})
