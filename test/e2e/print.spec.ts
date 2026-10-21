import { expect, test } from "@playwright/test"
import { login, scenario, type User } from "./support"

// 画面は #app-shell が画面の大きさに固定され、各部分がスクロールする作りなので、
// 印刷のときだけ枠とスクロールをやめて中身を紙に流す（application.css）

let data: { owner: User }

test.beforeAll(() => {
  data = scenario<{ owner: User }>("owner")
})

test("印刷すると、画面に見えているものが切れずに最後まで複数ページへ流れる", async ({ page }) => {
  await login(page, data.owner)
  // グループ管理は今は仮のデータ。「全社」の下位グループのメンバーは 77 人いる
  await page.goto("/management/groups/1")
  await page.getByText(/下位グループに所属するメンバー/).click()
  const rows = page.locator("#sub-member-list li:not([data-load-more])")
  // 開くと1ページ目（30人）を読み込み、下までスクロールするたびに続きを読み足す
  await expect(rows).toHaveCount(30)
  for (const count of [60, 77]) {
    await page.locator("[data-load-more]").scrollIntoViewIfNeeded()
    await expect(rows).toHaveCount(count)
  }

  await page.emulateMedia({ media: "print" })
  // 画面では1枚分の高さに収まっていた本文が、紙では最後の行まで流れる
  const pdf = (await page.pdf({ format: "A4" })).toString("latin1")
  expect(pdf.match(/\/Type\s*\/Page[^s]/g)?.length).toBeGreaterThan(2)
  const bottom = await rows.last().evaluate((row) => row.getBoundingClientRect().bottom + window.scrollY)
  expect(bottom).toBeGreaterThan(page.viewportSize()!.height)
})
