// ラベルを複数入力する欄。打つと既存のラベルから候補を出し、確定するとチップにする。
//
// <label-input data-suggestions='["営業","開発"]' data-add-text="「%{name}」を追加"
//              data-remove-text="%{name}を外す">
//   <input type="text" name="..." value="営業, 本部" id="...">
// </label-input>
//
// 中の input は JavaScript が無くてもカンマ区切りの入力欄として使える。動くときはそれを
// type=hidden の値の入れ物に変え、id は文字を打つ欄に移す（<label for> がそこを指すように）

const SEPARATOR = /[,、]/

export const parseLabels = (text: string): string[] => {
  const labels = text.split(SEPARATOR).map((label) => label.trim()).filter((label) => label !== "")
  return [...new Set(labels)]
}

type Option = { name: string, isNew: boolean }

export class LabelInput extends HTMLElement {
  #labels: string[] = []
  #suggestions: string[] = []
  #options: Option[] = []
  #active = -1
  #hidden?: HTMLInputElement
  #text?: HTMLInputElement
  #chips?: HTMLElement
  #list?: HTMLUListElement

  connectedCallback() {
    const fallback = this.querySelector("input")
    if (this.#text || !fallback) return

    this.#suggestions = JSON.parse(this.dataset.suggestions ?? "[]")
    this.#labels = parseLabels(fallback.value)
    this.#hidden = fallback

    const listId = `${fallback.id || fallback.name}-options`
    const text = document.createElement("input")
    text.type = "text"
    text.id = fallback.id
    text.autocomplete = "off"
    text.setAttribute("role", "combobox")
    text.setAttribute("aria-autocomplete", "list")
    text.setAttribute("aria-controls", listId)
    text.setAttribute("aria-expanded", "false")
    text.className = "min-w-24 flex-1 border-0 bg-transparent p-0.5 text-sm outline-hidden"
    fallback.removeAttribute("id")
    fallback.type = "hidden"
    this.#text = text

    const box = document.createElement("div")
    box.className = "input flex cursor-text flex-wrap items-center gap-1.5 py-1.5 "
      + "focus-within:border-primary-600 focus-within:ring-3 focus-within:ring-primary-600/20"
    this.#chips = document.createElement("span")
    this.#chips.className = "contents"
    box.append(this.#chips, text)
    box.addEventListener("click", () => text.focus())

    const list = document.createElement("ul")
    list.id = listId
    list.setAttribute("role", "listbox")
    list.hidden = true
    list.className = "absolute inset-x-0 top-full z-10 mt-1 max-h-60 overflow-y-auto rounded-xl bg-white py-1.5 text-sm shadow-lg ring-1 ring-slate-900/10"
    // 押した時点で入力欄からフォーカスが外れると、blur で一覧が閉じて選べなくなる
    list.addEventListener("mousedown", (event) => event.preventDefault())
    list.addEventListener("click", (event) => {
      const option = (event.target as Element).closest<HTMLElement>("[data-index]")
      if (option) this.#choose(Number(option.dataset.index))
    })
    this.#list = list

    this.classList.add("relative", "block")
    this.append(box, list)

    text.addEventListener("input", () => this.#onInput())
    text.addEventListener("keydown", (event) => this.#onKeydown(event))
    text.addEventListener("focus", () => this.#refresh())
    // 打ちかけのまま離れたら、そこまでを確定する
    text.addEventListener("blur", () => {
      this.#add(text.value)
      text.value = ""
      this.#close()
    })

    this.#render()
  }

  get labels(): string[] {
    return [...this.#labels]
  }

  #onInput() {
    const text = this.#text!
    // カンマや読点を打ったら、そこまでを確定する
    if (SEPARATOR.test(text.value)) {
      const parts = text.value.split(SEPARATOR)
      text.value = parts.pop() ?? ""
      parts.forEach((part) => this.#add(part))
    }
    this.#refresh()
  }

  #onKeydown(event: KeyboardEvent) {
    const text = this.#text!
    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp":
        if (this.#options.length === 0) return
        event.preventDefault()
        this.#active = (this.#active + (event.key === "ArrowDown" ? 1 : -1) + this.#options.length) % this.#options.length
        this.#renderList()
        break
      case "Enter":
        // フォームを送信させない。確定するものが無いときだけ送信に回す
        if (this.#active >= 0) {
          event.preventDefault()
          this.#choose(this.#active)
        } else if (text.value.trim() !== "") {
          event.preventDefault()
          this.#add(text.value)
          text.value = ""
          this.#refresh()
        }
        break
      case "Escape":
        this.#close()
        break
      case "Backspace":
        if (text.value === "" && this.#labels.length > 0) this.#remove(this.#labels.length - 1)
        break
    }
  }

  #choose(index: number) {
    const option = this.#options[index]
    if (!option) return
    this.#add(option.name)
    this.#text!.value = ""
    this.#refresh()
  }

  #add(name: string) {
    const label = name.trim()
    if (label === "" || this.#labels.includes(label)) return
    this.#labels.push(label)
    this.#render()
  }

  #remove(index: number) {
    this.#labels.splice(index, 1)
    this.#render()
    this.#refresh()
  }

  // 打った文字に合わせて候補を作り直す。既に付いているものは出さない
  #refresh() {
    const query = this.#text!.value.trim()
    const candidates = this.#suggestions.filter((name) => !this.#labels.includes(name) && name.includes(query))
    this.#options = candidates.map((name) => ({ name, isNew: false }))
    if (query !== "" && !this.#suggestions.includes(query) && !this.#labels.includes(query)) {
      this.#options.push({ name: query, isNew: true })
    }
    this.#active = query !== "" && this.#options.length > 0 ? 0 : -1
    this.#renderList()
  }

  #close() {
    this.#options = []
    this.#active = -1
    this.#renderList()
  }

  #render() {
    this.#hidden!.value = this.#labels.join(", ")
    this.#chips!.replaceChildren(...this.#labels.map((label, index) => {
      const chip = document.createElement("span")
      chip.className = "inline-flex items-center gap-1 rounded-full bg-slate-100 py-0.5 pr-1 pl-2.5 text-sm text-slate-700"
      chip.textContent = label
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "rounded-full px-1 text-slate-500 hover:bg-slate-900/10 hover:text-slate-800"
      remove.setAttribute("aria-label", (this.dataset.removeText ?? "%{name}").replace("%{name}", label))
      remove.textContent = "×"
      remove.addEventListener("click", (event) => {
        event.stopPropagation()
        this.#remove(index)
        this.#text!.focus()
      })
      chip.append(remove)
      return chip
    }))
  }

  #renderList() {
    const list = this.#list!
    const text = this.#text!
    list.replaceChildren(...this.#options.map((option, index) => {
      const item = document.createElement("li")
      item.id = `${list.id}-${index}`
      item.dataset.index = String(index)
      item.setAttribute("role", "option")
      item.setAttribute("aria-selected", String(index === this.#active))
      item.className = "cursor-pointer px-4 py-1.5 " + (index === this.#active ? "bg-primary-50 text-primary-900" : "hover:bg-slate-50")
      item.textContent = option.isNew
        ? (this.dataset.addText ?? "%{name}").replace("%{name}", option.name)
        : option.name
      return item
    }))
    const open = this.#options.length > 0 && document.activeElement === text
    list.hidden = !open
    text.setAttribute("aria-expanded", String(open))
    if (this.#active >= 0) {
      text.setAttribute("aria-activedescendant", `${list.id}-${this.#active}`)
    } else {
      text.removeAttribute("aria-activedescendant")
    }
  }
}

if (!customElements.get("label-input")) customElements.define("label-input", LabelInput)
