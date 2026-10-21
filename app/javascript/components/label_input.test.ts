import { afterEach, beforeEach, describe, expect, test } from "vitest"
import { LabelInput, parseLabels } from "./label_input"

describe("parseLabels", () => {
  test("カンマと読点で分け、前後の空白・空・重複を除く", () => {
    expect(parseLabels(" 営業, 本部、営業,, ")).toEqual(["営業", "本部"])
  })
})

describe("<label-input>", () => {
  let element: LabelInput
  const text = () => document.getElementById("group_labels") as HTMLInputElement
  const hidden = () => element.querySelector<HTMLInputElement>("input[type=hidden]")!
  const options = () => [...element.querySelectorAll("[role=option]")].map((option) => option.textContent)
  const type = (value: string) => {
    text().value = value
    text().dispatchEvent(new Event("input"))
  }
  const press = (key: string) => {
    const event = new KeyboardEvent("keydown", { key, cancelable: true })
    text().dispatchEvent(event)
    return event
  }

  beforeEach(() => {
    document.body.innerHTML = `
      <label for="group_labels">ラベル</label>
      <label-input data-suggestions='["営業","開発","本部"]' data-add-text="「%{name}」を追加" data-remove-text="%{name}を外す">
        <input type="text" name="group_labels" id="group_labels" value="営業">
      </label-input>`
    element = document.querySelector("label-input")!
    text().focus()
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  test("初めの値をチップにし、送る値は隠しの入力に入れる", () => {
    expect(element.labels).toEqual(["営業"])
    expect(hidden().name).toBe("group_labels")
    expect(hidden().value).toBe("営業")
    expect(text().getAttribute("role")).toBe("combobox")
  })

  test("打った文字を含む既存のラベルを候補に出し、付いているものは出さない", () => {
    type("本")
    expect(options()).toEqual(["本部", "「本」を追加"])

    type("")
    expect(options()).toEqual(["開発", "本部"])
  })

  test("Enter で先頭の候補を確定し、フォームは送信させない", () => {
    type("開")
    const event = press("Enter")

    expect(event.defaultPrevented).toBe(true)
    expect(element.labels).toEqual(["営業", "開発"])
    expect(hidden().value).toBe("営業, 開発")
    expect(text().value).toBe("")
  })

  test("候補に無い名前は新しいラベルとして付けられる", () => {
    type("東日本")
    expect(options()).toEqual(["「東日本」を追加"])
    press("Enter")

    expect(element.labels).toEqual(["営業", "東日本"])
  })

  test("矢印キーで選ぶ候補を変えられる", () => {
    type("")
    press("ArrowDown")
    press("ArrowDown")
    press("Enter")

    expect(element.labels).toEqual(["営業", "本部"])
  })

  test("カンマや読点を打つと、そこまでを確定する", () => {
    type("東日本、西日本,")
    expect(element.labels).toEqual(["営業", "東日本", "西日本"])
    expect(text().value).toBe("")
  })

  test("空の欄で Backspace を押すと最後のチップを外し、× でも外せる", () => {
    type("開発,")
    press("Backspace")
    expect(element.labels).toEqual(["営業"])

    element.querySelector<HTMLButtonElement>("button[aria-label='営業を外す']")!.click()
    expect(element.labels).toEqual([])
    expect(hidden().value).toBe("")
  })

  test("確定するものが無い Enter は、フォームの送信に回す", () => {
    type("")
    expect(press("Enter").defaultPrevented).toBe(false)
  })

  test("打ちかけのまま離れたら確定する", () => {
    type("本部")
    text().blur()

    expect(element.labels).toEqual(["営業", "本部"])
    expect(text().value).toBe("")
  })
})
