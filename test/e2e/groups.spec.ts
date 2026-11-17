import { expect, test } from "@playwright/test"
import { login, scenario, type User } from "./support"

let data: { owner: User, groups: { company: number, platform: number } }

test.beforeAll(() => {
  data = scenario<typeof data>("groups")
})

test("メンバーの編集の画面で、ダイアログから探して選んだ人を足し、グループ管理者にしてまとめて保存する", async ({ page }) => {
  await login(page, data.owner)
  await page.goto(`/management/groups/${data.groups.company}`)
  await page.getByLabel("グループの操作").click()
  await page.getByRole("link", { name: "メンバーを編集" }).click()

  await page.getByRole("button", { name: "メンバーを追加" }).click()
  const dialog = page.getByRole("dialog", { name: "メンバーを追加" })
  await expect(dialog.getByRole("checkbox")).toHaveCount(30)
  await dialog.getByRole("searchbox").fill("開発 0")
  await expect(dialog.getByRole("checkbox")).toHaveCount(10)
  await dialog.getByRole("checkbox", { name: /開発 03/ }).check()
  await dialog.getByRole("checkbox", { name: /開発 05/ }).check()
  await dialog.getByRole("button", { name: "追加する" }).click()
  await expect(dialog).toBeHidden()

  const members = page.locator("#direct-members")
  await expect(members.getByRole("heading")).toHaveText("所属メンバー（2人）")
  await members.getByRole("row", { name: /開発 05/ }).getByRole("checkbox", { name: "管理者" }).check()

  // もう一度開くと、足した人は選べない
  await page.getByRole("button", { name: "メンバーを追加" }).click()
  await dialog.getByRole("searchbox").fill("開発 03")
  await expect(dialog.getByRole("checkbox", { name: /開発 03/ })).toBeDisabled()
  await dialog.getByRole("button", { name: "キャンセル" }).click()

  await page.getByRole("button", { name: "保存する" }).click()
  await expect(page.getByRole("status")).toHaveText("保存しました。")
  await expect(page.locator("#direct-members tr")).toHaveText([/開発 05\s*管理者/, /開発 03/])
})

test("上位グループは、ダイアログのツリーで選び、決定で欄に出してから保存する", async ({ page }) => {
  await login(page, data.owner)
  await page.goto(`/management/groups/${data.groups.platform}/edit`)
  const field = page.locator("#group-parent [data-selected-path]")
  await expect(field).toHaveText(/全社\s*>\s*開発部/)

  await page.getByRole("button", { name: "変更" }).click()
  const dialog = page.getByRole("dialog", { name: "上位グループを選ぶ" })
  await expect(dialog.getByRole("radio", { name: "開発部" })).toBeChecked()
  await expect(dialog.getByRole("radio", { name: "基盤チーム" })).toBeDisabled()
  // 選ばれていない「営業部」は閉じている。名前を押すと選ぶだけで、開くのは三角
  const tokyo = dialog.getByRole("radio", { name: "東京チーム" })
  await expect(tokyo).toBeHidden()
  await dialog.getByText("営業部", { exact: true }).click()
  await expect(dialog.getByRole("radio", { name: "営業部" })).toBeChecked()
  await expect(tokyo).toBeHidden()
  await dialog.locator("summary", { hasText: "営業部" }).locator("span").first().click()
  await tokyo.check()

  // キャンセルでは戻る
  await dialog.getByRole("button", { name: "キャンセル" }).click()
  await expect(field).toHaveText(/全社\s*>\s*開発部/)
  await page.getByRole("button", { name: "変更" }).click()
  await expect(dialog.getByRole("radio", { name: "開発部" })).toBeChecked()

  await tokyo.check()
  await dialog.getByRole("button", { name: "決定" }).click()
  await expect(dialog).toBeHidden()
  await expect(field).toHaveText(/全社\s*>\s*営業部\s*>\s*東京チーム/)
  await page.getByRole("button", { name: "保存する" }).click()
  await expect(page.locator("#group-parent-path")).toHaveText(/全社\s*›\s*営業部\s*›\s*東京チーム/)
})
