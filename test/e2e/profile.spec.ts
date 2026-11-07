import { expect, test } from "@playwright/test"
import { login, scenario, type User } from "./support"

let data: { owner: User }

test.beforeAll(() => {
  data = scenario<typeof data>("users")
})

test("個人設定で画像を選び、丸に入れる範囲を動かしてアバターにする", async ({ page }) => {
  await login(page, data.owner)
  await page.goto("/profile")

  // 左半分が黒、右半分が白の横長の画像（300×150）
  const png = await page.evaluate(() => {
    const canvas = document.createElement("canvas")
    canvas.width = 300
    canvas.height = 150
    const context = canvas.getContext("2d")!
    context.fillStyle = "#000"
    context.fillRect(0, 0, 150, 150)
    context.fillStyle = "#fff"
    context.fillRect(150, 0, 150, 150)
    return canvas.toDataURL("image/png").split(",")[1]
  })
  await page.locator("#avatar-file").setInputFiles({ name: "photo.png", mimeType: "image/png", buffer: Buffer.from(png, "base64") })

  const dialog = page.getByRole("dialog", { name: "アバターの範囲を調整" })
  await expect(dialog).toBeVisible()
  // 初めは中央。左へいっぱいに動かして、白い右半分を枠に入れる
  const area = dialog.getByRole("application")
  const box = (await area.boundingBox())!
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2)
  await page.mouse.down()
  await page.mouse.move(box.x - box.width, box.y + box.height / 2, { steps: 5 })
  await page.mouse.up()
  await dialog.getByRole("button", { name: "設定する" }).click()

  await expect(page.getByText("アバターを設定しました。")).toBeVisible()
  const avatar = page.locator("#avatar img[src^='/avatars/']")
  await expect(avatar).toBeVisible()
  await expect(page.locator("details[data-dropdown] summary img")).toHaveAttribute("src", (await avatar.getAttribute("src"))!)
  const brightness = await avatar.evaluate(async (image: HTMLImageElement) => {
    await image.decode()
    const canvas = document.createElement("canvas")
    canvas.width = image.naturalWidth
    canvas.height = image.naturalHeight
    const context = canvas.getContext("2d")!
    context.drawImage(image, 0, 0)
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data
    let sum = 0
    for (let i = 0; i < pixels.length; i += 4) sum += pixels[i]
    return sum / (pixels.length / 4)
  })
  expect(brightness).toBeGreaterThan(245)

  await page.getByRole("button", { name: "削除" }).click()
  await expect(page.getByText("アバターを削除しました。")).toBeVisible()
  await expect(page.locator("#avatar img[src]")).toHaveCount(0)
})
