// グループの編集の画面の、メンバーの欄。行を外す・ダイアログで探して足す、をフォームの中で行い、
// 送信はフォームの「保存する」でまとめて行う。
//
// <group-members data-candidates-url="/management/groups/1/member_candidates"
//                data-count-text="所属メンバー（%{count}人）" data-load-error="読み込めませんでした。">
//   <h3 data-count>…</h3> <button data-open-dialog>
//   <p data-empty> <table><tbody data-rows> 行（tr[data-member-row="tenant_user_id"]）
//   <template data-row-template> 足すときに複製する行
//   <dialog> <input data-search> <ul data-candidates> <button data-add-members> <button data-close-dialog>
// </group-members>
//
// 候補の一覧はサーバが返す HTML（li の中に input[type=checkbox][value=tenant_user_id][data-name][data-email]）
import { observeLoadMore } from "~/components/load_more"

const SEARCH_DELAY = 300

export class GroupMembers extends HTMLElement {
  #searchTimer?: ReturnType<typeof setTimeout>
  #request = 0

  connectedCallback() {
    if (this.dataset.ready) return
    this.dataset.ready = "true"

    this.addEventListener("click", (event) => this.#onClick(event))
    const search = this.#search()
    search.addEventListener("input", () => {
      clearTimeout(this.#searchTimer)
      this.#searchTimer = setTimeout(() => this.#load(), SEARCH_DELAY)
    })
    // フォームの中にあるので、Enter で「保存する」が押されないようにする
    search.addEventListener("keydown", (event) => {
      if (event.key !== "Enter") return
      event.preventDefault()
      clearTimeout(this.#searchTimer)
      this.#load()
    })
    // 読み足した候補にも「追加済み」の印を付ける
    new MutationObserver(() => this.#markAdded()).observe(this.#candidates(), { childList: true })
  }

  #onClick(event: Event) {
    const target = event.target as Element
    if (target.closest("[data-open-dialog]")) {
      this.#open()
    } else if (target.closest("[data-close-dialog]")) {
      this.#dialog().close()
    } else if (target.closest("[data-add-members]")) {
      this.#add()
    } else if (target.closest("[data-remove-member]")) {
      target.closest("tr")?.remove()
      this.#refresh()
    }
  }

  async #open() {
    this.#search().value = ""
    this.#candidates().replaceChildren()
    this.#dialog().showModal()
    this.#search().focus()
    await this.#load()
  }

  async #load() {
    const request = ++this.#request
    const url = new URL(this.dataset.candidatesUrl ?? "", window.location.href)
    const query = this.#search().value.trim()
    if (query !== "") url.searchParams.set("q", query)

    let html: string | undefined
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } })
      if (response.ok) html = await response.text()
    } catch {
      // 通信の失敗も、読み込めなかったときと同じに扱う
    }
    // 打っている途中の古い検索の結果が、後から届いて上書きしないように
    if (request !== this.#request) return

    if (html === undefined) {
      const error = document.createElement("li")
      error.setAttribute("role", "alert")
      error.className = "py-3 text-center text-sm text-red-700"
      error.textContent = this.dataset.loadError ?? ""
      this.#candidates().replaceChildren(error)
      return
    }
    this.#candidates().innerHTML = html
    observeLoadMore()
  }

  #add() {
    const template = this.querySelector<HTMLTemplateElement>("template[data-row-template]")!
    const checked = this.#candidates().querySelectorAll<HTMLInputElement>("input[type=checkbox]:checked:not(:disabled)")
    for (const input of checked) {
      const row = (template.content.firstElementChild as HTMLElement).cloneNode(true) as HTMLElement
      row.dataset.memberRow = input.value
      row.querySelector("[data-name]")!.textContent = input.dataset.name ?? ""
      row.querySelector("[data-email]")!.textContent = input.dataset.email ?? ""
      row.querySelectorAll("input").forEach((field) => {
        field.name = `group[members][${input.value}]`
      })
      this.querySelector("[data-rows]")!.append(row)
    }
    this.#dialog().close()
    this.#refresh()
  }

  #markAdded() {
    const added = new Set([...this.querySelectorAll<HTMLElement>("[data-member-row]")].map((row) => row.dataset.memberRow))
    this.#candidates().querySelectorAll<HTMLInputElement>("input[type=checkbox]").forEach((input) => {
      if (!added.has(input.value)) return
      input.checked = true
      input.disabled = true
    })
  }

  #refresh() {
    const count = this.querySelectorAll("[data-member-row]").length
    this.querySelector("[data-count]")!.textContent = (this.dataset.countText ?? "").replace("%{count}", String(count))
    this.querySelector<HTMLElement>("[data-empty]")!.hidden = count > 0
    this.querySelector<HTMLElement>("table")!.hidden = count === 0
  }

  #dialog() {
    return this.querySelector("dialog")!
  }

  #search() {
    return this.querySelector<HTMLInputElement>("[data-search]")!
  }

  #candidates() {
    return this.querySelector<HTMLElement>("[data-candidates]")!
  }
}

if (!customElements.get("group-members")) customElements.define("group-members", GroupMembers)
