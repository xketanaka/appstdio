import { beforeEach, describe, expect, test } from "vitest"
import type { ParentPicker } from "./parent_picker"
import "./parent_picker"

const option = (value: string, path: string[], checked = false) => `
  <label><input type="radio" name="group[parent_id]" value="${value}" data-path='${JSON.stringify(path)}'
    ${checked ? "checked" : ""}>${path.at(-1) ?? "最上位"}</label>`

describe("<parent-picker>", () => {
  let element: ParentPicker
  const dialog = () => element.querySelector("dialog")!
  const path = () => element.querySelector("[data-selected-path]")!.textContent!.replace(/\s+/g, "")
  const radio = (value: string) => element.querySelector<HTMLInputElement>(`input[value="${value}"]`)!
  const click = (selector: string) => element.querySelector<HTMLElement>(selector)!.click()

  beforeEach(() => {
    // jsdom の dialog は showModal / close を持たないことがあるので、open 属性だけ切り替えて close を送る
    HTMLDialogElement.prototype.showModal = function () {
      this.setAttribute("open", "")
    }
    HTMLDialogElement.prototype.close = function () {
      this.removeAttribute("open")
      this.dispatchEvent(new Event("close"))
    }
    document.body.innerHTML = `
      <form>
        <parent-picker data-no-parent="最上位">
          <span data-selected-path><span>全社</span></span>
          <button type="button" data-open-dialog>変更</button>
          <dialog>
            ${option("", [])}${option("1", ["全社"], true)}${option("2", ["全社", "営業部"])}
            <button type="button" data-close-dialog>キャンセル</button>
            <button type="button" data-choose>決定</button>
          </dialog>
        </parent-picker>
      </form>`
    element = document.querySelector("parent-picker")!
  })

  test("選んで決定すると、欄に最上位からの並びを出す", () => {
    click("[data-open-dialog]")
    expect(dialog().open).toBe(true)

    radio("2").checked = true
    click("[data-choose]")

    expect(dialog().open).toBe(false)
    expect(path()).toBe("全社>営業部")
    expect(new FormData(element.closest("form")!).get("group[parent_id]")).toBe("2")
  })

  test("最上位を選ぶと「最上位」と出す", () => {
    click("[data-open-dialog]")
    radio("").checked = true
    click("[data-choose]")

    expect(path()).toBe("最上位")
  })

  test("キャンセルで閉じると、開く前の選択に戻す", () => {
    click("[data-open-dialog]")
    radio("2").checked = true
    click("[data-close-dialog]")

    expect(radio("1").checked).toBe(true)
    expect(path()).toBe("全社")
  })

  test("ダイアログの中の Enter は決定として扱い、フォームを送らない", () => {
    click("[data-open-dialog]")
    radio("2").checked = true
    const event = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
    radio("2").dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(dialog().open).toBe(false)
    expect(path()).toBe("全社>営業部")
  })
})
