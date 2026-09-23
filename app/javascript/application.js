// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

// details/summary のプルダウンは、そのままだと外側をクリックしても閉じない
const closeDropdowns = (except) => {
  document.querySelectorAll("details[data-dropdown][open]").forEach((dropdown) => {
    if (dropdown !== except) dropdown.open = false
  })
}

const drawer = () => document.querySelector("[data-drawer]")

document.addEventListener("click", (event) => {
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

document.addEventListener("keydown", (event) => {
  // dialog の Esc は showModal が面倒を見るので、ここはプルダウンだけ
  if (event.key === "Escape") closeDropdowns(null)
})
