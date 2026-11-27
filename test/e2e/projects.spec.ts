import { expect, test } from "@playwright/test"
import { login, scenario, type User } from "./support"

let data: { sato: User }

test.beforeAll(() => {
  data = scenario<typeof data>("projects")
})

test("メニューからプロジェクトを開き、帯の「プロジェクト」から最近開いた別のプロジェクトへ切り替える", async ({ page }) => {
  await login(page, data.sato)
  await page.getByRole("button", { name: "メニューを開く" }).click()
  await page.getByRole("link", { name: "プロジェクト" }).click()
  await page.getByRole("link", { name: "社内改善" }).click()
  await expect(page.locator("#header-context")).toHaveText(/社内改善/)

  await page.goto("/projects")
  await page.getByRole("link", { name: "新製品開発" }).click()
  await expect(page.getByRole("heading", { name: "新製品開発" })).toBeVisible()

  const rail = page.getByRole("navigation", { name: "プロジェクトのメニュー" })
  await rail.getByLabel("プロジェクトを切り替える").click()
  const switcher = page.locator("#project-switcher")
  await expect(switcher.getByRole("link", { name: "新製品開発" })).toHaveAttribute("aria-current", "page")
  await switcher.getByRole("link", { name: "社内改善" }).click()
  await expect(page.getByRole("heading", { name: "社内改善" })).toBeVisible()
})
