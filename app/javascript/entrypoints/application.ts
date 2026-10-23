import "~/components/label_input"
import "~/components/group_members"
import { observeLoadMore } from "~/components/load_more"

const closeDropdowns = (except: Element | null) => {
  document.querySelectorAll<HTMLDetailsElement>("details[data-dropdown][open]").forEach((dropdown) => {
    if (dropdown !== except) dropdown.open = false
  })
}

const drawer = () => document.querySelector<HTMLDialogElement>("[data-drawer]")

document.addEventListener("click", (event) => {
  if (!(event.target instanceof Element)) return

  closeDropdowns(event.target.closest("details[data-dropdown]"))

  if (event.target.closest("[data-drawer-open]")) {
    drawer()?.showModal()
  } else if (event.target.closest("[data-drawer-close]")) {
    drawer()?.close()
  } else if (event.target.matches("[data-drawer]")) {
    // dialog 自身がクリック対象になるのは backdrop を押したとき
    drawer()?.close()
  }
})

// 絞り込みのチェックボックスなど、変えたらすぐ送るもの
document.addEventListener("change", (event) => {
  if (event.target instanceof HTMLInputElement && event.target.matches("[data-auto-submit]")) {
    event.target.form?.requestSubmit()
  }
})

document.addEventListener("keydown", (event) => {
  // dialog の Esc は showModal が面倒を見るので、ここはプルダウンだけ
  if (event.key === "Escape") closeDropdowns(null)
})

observeLoadMore()
