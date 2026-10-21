import "~/components/label_input"

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

document.addEventListener("keydown", (event) => {
  // dialog の Esc は showModal が面倒を見るので、ここはプルダウンだけ
  if (event.key === "Escape") closeDropdowns(null)
})

// data-load-more の行が画面に見えたら、その URL の HTML（続きの行）を読んでこの行と置き換える。
// 返ってきた HTML の末尾に次の data-load-more があれば、それも見張る（下までスクロールで読み足し）。
// 閉じた details の中は見えない扱いなので、開くまで読み込まない
const loadMore = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (!entry.isIntersecting || !(entry.target instanceof HTMLElement)) continue

    const row = entry.target
    loadMore.unobserve(row)
    fetch(row.dataset.loadMore ?? "", { headers: { Accept: "text/html" } })
      .then((response) => {
        if (!response.ok) throw new Error(response.statusText)
        return response.text()
      })
      .then((html) => {
        row.insertAdjacentHTML("beforebegin", html)
        row.remove()
        observeLoadMore()
      })
      .catch(() => {
        row.textContent = row.dataset.loadError ?? ""
      })
  }
})

const observeLoadMore = () => {
  document.querySelectorAll("[data-load-more]").forEach((row) => loadMore.observe(row))
}

observeLoadMore()
