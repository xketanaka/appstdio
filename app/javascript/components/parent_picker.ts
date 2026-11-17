// 上位グループの欄。「変更」でダイアログを開き、ツリーのラジオボタンで選んで「決定」で欄の表示に反映する。
// ラジオボタンがそのままフォームの値なので、キャンセル・Esc で閉じたら開く前の選択に戻す。
//
// <parent-picker data-no-parent="最上位">
//   <span data-selected-path>表示</span> <button data-open-dialog>
//   <dialog> input[type=radio][data-path='["全社","営業部"]'] … <button data-close-dialog> <button data-choose>
// </parent-picker>
export class ParentPicker extends HTMLElement {
  #saved: HTMLInputElement | null = null

  connectedCallback() {
    if (this.dataset.ready) return
    this.dataset.ready = "true"

    this.addEventListener("click", (event) => {
      const target = event.target as Element
      if (target.closest("[data-open-dialog]")) {
        this.#open()
      } else if (target.closest("[data-close-dialog]")) {
        this.#dialog().close()
      } else if (target.closest("[data-choose]")) {
        this.#choose()
      }
    })
    // フォームの中にあるので、Enter で「保存する」が押されないよう、決定として扱う
    this.#dialog().addEventListener("keydown", (event) => {
      if (event.key !== "Enter" || (event.target as Element).closest("button")) return
      event.preventDefault()
      this.#choose()
    })
    // 決定のときは #saved を選んだものにしてから閉じるので、ここで戻しても変わらない
    this.#dialog().addEventListener("close", () => {
      if (this.#saved) this.#saved.checked = true
    })
  }

  #open() {
    this.#saved = this.#checked()
    this.#dialog().showModal()
    this.#saved?.scrollIntoView?.({ block: "nearest" })
    this.#saved?.focus()
  }

  #choose() {
    this.#saved = this.#checked()
    const names: string[] = JSON.parse(this.#saved?.dataset.path ?? "[]")
    const parts = names.length === 0 ? [this.dataset.noParent ?? ""] : names
    const path = this.querySelector<HTMLElement>("[data-selected-path]")!
    path.replaceChildren()
    parts.forEach((name, i) => {
      if (i > 0) {
        const separator = document.createElement("span")
        separator.className = "mx-1 text-slate-400"
        separator.setAttribute("aria-hidden", "true")
        separator.textContent = ">"
        path.append(separator)
      }
      const span = document.createElement("span")
      span.textContent = name
      path.append(span)
    })
    this.#dialog().close()
  }

  #checked() {
    return this.querySelector<HTMLInputElement>("dialog input[type=radio]:checked")
  }

  #dialog() {
    return this.querySelector<HTMLDialogElement>("dialog")!
  }
}

if (!customElements.get("parent-picker")) customElements.define("parent-picker", ParentPicker)
