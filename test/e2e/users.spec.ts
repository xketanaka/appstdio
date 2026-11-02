import { expect, test } from "@playwright/test"
import { login, scenario, type User } from "./support"

let data: { owner: User, users: { sato: number } }

test.beforeAll(() => {
  data = scenario<typeof data>("users")
})

test("利用者の編集の画面で、ダイアログから探して選んだグループを足し、外したグループと一緒にまとめて保存する", async ({ page }) => {
  await login(page, data.owner)
  await page.goto(`/management/users/${data.users.sato}`)
  await page.getByRole("link", { name: "編集" }).click()

  const groups = page.locator("#user-groups")
  await expect(groups.getByRole("heading")).toHaveText("所属グループ（1件）")
  await page.getByRole("button", { name: "所属グループを追加" }).click()
  const dialog = page.getByRole("dialog", { name: "所属グループを追加" })
  // すでに所属している営業部は選べない
  await expect(dialog.getByRole("checkbox", { name: /営業部/ })).toBeDisabled()
  await dialog.getByRole("searchbox").fill("開発")
  await expect(dialog.getByRole("checkbox")).toHaveCount(1)
  await dialog.getByRole("checkbox", { name: /開発部/ }).check()
  await dialog.getByRole("button", { name: "追加する" }).click()
  await expect(dialog).toBeHidden()

  await groups.getByRole("row", { name: /営業部/ }).getByRole("button", { name: "削除" }).click()
  await expect(groups.getByRole("heading")).toHaveText("所属グループ（1件）")
  await page.getByRole("button", { name: "保存する" }).click()

  await expect(page.getByText("保存しました。")).toBeVisible()
  await expect(page.locator("#user-groups").getByRole("row")).toHaveText([/開発部\s*全社/])
})
