// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

// details/summary のプルダウンは、そのままだと外側をクリックしても閉じない
const closeDropdowns = (except) => {
  document.querySelectorAll("details[data-dropdown][open]").forEach((dropdown) => {
    if (dropdown !== except) dropdown.open = false
  })
}

document.addEventListener("click", (event) => {
  closeDropdowns(event.target.closest("details[data-dropdown]"))
})

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeDropdowns(null)
})
