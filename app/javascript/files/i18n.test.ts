import { beforeEach, expect, test } from "vitest"
import { setMessages, t } from "./i18n"

beforeEach(() => {
  setMessages({ drives: { others: "%{name} のマイドライブ" }, title: "ファイル" })
})

test("入れ子のキーを引き、%{name} を埋める", () => {
  expect(t("title")).toBe("ファイル")
  expect(t("drives.others", { name: "田中" })).toBe("田中 のマイドライブ")
})

test("無いキーは例外にする", () => {
  expect(() => t("drives.nothing")).toThrow("Translation missing: files_app.drives.nothing")
  expect(() => t("drives")).toThrow()
})
