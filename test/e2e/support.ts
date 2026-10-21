import { execFileSync } from "node:child_process"
import { expect, type Page } from "@playwright/test"

export type User = { email: string, password: string }

// テスト専用のテナントとデータを作る（test/e2e/scenarios.rb）。Rails を起動するので1〜2秒かかる
export function scenario<T>(name: string): T {
  const output = execFileSync("bin/rails", [`e2e:scenario[${name}]`], {
    env: { ...process.env, RAILS_ENV: "test", DB_NAME: "appstdio_e2e" },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  })
  return JSON.parse(output.trim().split("\n").at(-1) ?? "")
}

export async function login(page: Page, user: User) {
  await page.goto("/login")
  await page.getByLabel("メールアドレス").fill(user.email)
  await page.getByLabel("パスワード").fill(user.password)
  await page.getByRole("button", { name: "ログイン" }).click()
  await expect(page.getByRole("heading", { name: "ログインしています" })).toBeVisible()
}
