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

test("ドラッグして一覧や左ペインのフォルダへ移し、知らせから元に戻せる", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files/my_drive")
  const list = page.locator("#file-list")
  const notice = page.getByRole("status").filter({ hasText: "しました" })
  const minutes = list.getByRole("row", { name: /議事録\.txt/ })

  await minutes.dragTo(list.getByRole("row", { name: /資料/ }))
  await expect(notice).toContainText("「議事録.txt」を「資料」に移動しました")
  await expect(minutes).toHaveCount(0)

  await notice.getByRole("button", { name: "元に戻す" }).click()
  await expect(notice).toContainText("移動を元に戻しました")
  await expect(minutes).toHaveCount(1)

  await minutes.dragTo(page.locator("#side-pane").getByRole("link", { name: "資料" }))
  await expect(notice).toContainText("「議事録.txt」を「資料」に移動しました")
  await page.locator("#side-pane").getByRole("link", { name: "資料" }).click()
  await expect(page.getByRole("heading", { name: "資料" })).toBeVisible()
  await expect(minutes).toHaveCount(1)
})

test("ファイルを選んで、またはパソコンから落としてアップロードし、ダブルクリックでダウンロードする", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files/my_drive")
  const list = page.locator("#file-list")
  const panel = page.getByRole("region", { name: "アップロード" })

  await page.locator("summary", { hasText: "作成" }).click()
  const [chooser] = await Promise.all([
    page.waitForEvent("filechooser"),
    page.getByRole("button", { name: "ファイルをアップロード" }).click(),
  ])
  await chooser.setFiles({ name: "報告書.txt", mimeType: "text/plain", buffer: Buffer.from("報告の中身") })
  await expect(panel).toContainText("1/1件 完了")
  await expect(list.getByRole("row", { name: /報告書\.txt/ })).toBeVisible()

  // パソコンから落とす操作は、ファイルを持った DataTransfer で dragover と drop を起こして再現する
  const files = await page.evaluateHandle(() => {
    const transfer = new DataTransfer()
    transfer.items.add(new File(["受領の中身"], "受領書.txt", { type: "text/plain" }))
    return transfer
  })
  await list.dispatchEvent("dragover", { dataTransfer: files })
  await list.dispatchEvent("drop", { dataTransfer: files })
  await expect(panel).toContainText("2/2件 完了")
  await expect(list.getByRole("row", { name: /受領書\.txt/ })).toBeVisible()

  const [download] = await Promise.all([
    page.waitForEvent("download"),
    list.getByRole("row", { name: /報告書\.txt/ }).dblclick(),
  ])
  expect(download.suggestedFilename()).toBe("報告書.txt")
  const body = await download.createReadStream()
  const chunks: Buffer[] = []
  for await (const chunk of body) chunks.push(chunk as Buffer)
  expect(Buffer.concat(chunks).toString()).toBe("報告の中身")
})

test("名前を変え、削除して知らせから戻し、ゴミ箱からも元に戻す", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files/my_drive")
  const list = page.locator("#file-list")
  const notice = page.getByRole("status").filter({ hasText: "しました" })

  // 開いたときは拡張子を除いた部分だけが選ばれているので、打ち込めば拡張子は残る
  await list.getByRole("row", { name: /変更前\.txt/ }).getByRole("group").click()
  await list.getByRole("row", { name: /変更前\.txt/ }).getByRole("button", { name: "名前を変更" }).click()
  const dialog = page.getByRole("dialog", { name: "名前を変更" })
  await page.keyboard.type("変更後")
  await dialog.getByRole("button", { name: "変更" }).click()
  await expect(dialog).toBeHidden()
  await expect(list.getByRole("row", { name: /変更後\.txt/ })).toBeVisible()

  const unneeded = list.getByRole("row", { name: /不要\.txt/ })
  await unneeded.click()
  await page.getByRole("toolbar").getByRole("button", { name: "削除" }).click()
  await expect(notice).toContainText("「不要.txt」をゴミ箱に移動しました")
  await expect(unneeded).toHaveCount(0)
  await notice.getByRole("button", { name: "元に戻す" }).click()
  await expect(notice).toContainText("削除を元に戻しました")
  await expect(unneeded).toHaveCount(1)

  await unneeded.click()
  await page.keyboard.press("Delete")
  await expect(unneeded).toHaveCount(0)

  await page.locator("#side-pane").getByRole("link", { name: "ゴミ箱" }).click()
  await list.getByRole("row", { name: /不要\.txt/ }).click()
  await page.getByRole("toolbar").getByRole("button", { name: "元に戻す" }).click()
  await expect(notice).toContainText("「不要.txt」を元に戻しました")
  await expect(list.getByRole("row", { name: /不要\.txt/ })).toHaveCount(0)

  await page.locator("#side-pane").getByRole("link", { name: "マイドライブ" }).click()
  await expect(unneeded).toHaveCount(1)
})

test("同じ名前で上げると新しい版になり、版の履歴でラベルを付けて古い版を最新に戻せる", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/files/my_drive")
  const list = page.locator("#file-list")
  const spec = list.getByRole("row", { name: /仕様書\.txt/ })

  await page.locator("summary", { hasText: "作成" }).click()
  const [chooser] = await Promise.all([
    page.waitForEvent("filechooser"),
    page.getByRole("button", { name: "ファイルをアップロード" }).click(),
  ])
  await chooser.setFiles({ name: "仕様書.txt", mimeType: "text/plain", buffer: Buffer.from("第2版の中身") })
  await expect(page.getByRole("region", { name: "アップロード" })).toContainText("「仕様書.txt」の版2として保存しました")
  await expect(spec).toHaveCount(1)

  await spec.getByRole("group").click()
  await spec.getByRole("button", { name: "版の履歴" }).click()
  const panel = page.getByRole("dialog", { name: "「仕様書.txt」の版の履歴" })
  const first = panel.getByRole("listitem").filter({ hasText: "版1" })
  await expect(panel.getByRole("listitem").first()).toContainText("版2最新")

  await first.getByRole("button", { name: "ラベルを付ける" }).click()
  await first.getByLabel("ラベル").fill("初版")
  await first.getByRole("button", { name: "保存" }).click()
  await expect(first).toContainText("初版")

  await first.getByRole("button", { name: "この版を最新に戻す" }).click()
  await expect(page.getByRole("status").filter({ hasText: "版1の中身で、版3を作りました" })).toBeVisible()
  await expect(panel.getByRole("listitem").first()).toContainText("版3最新")
  await panel.getByRole("button", { name: "版の履歴を閉じる" }).click()

  const [download] = await Promise.all([page.waitForEvent("download"), spec.dblclick()])
  const chunks: Buffer[] = []
  for await (const chunk of await download.createReadStream()) chunks.push(chunk as Buffer)
  expect(Buffer.concat(chunks).toString()).toBe("初版の中身")
})
