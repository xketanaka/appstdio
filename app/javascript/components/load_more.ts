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

// 後から HTML を差し込んだときも、これを呼べば中の data-load-more を見張り始める
export const observeLoadMore = () => {
  document.querySelectorAll("[data-load-more]").forEach((row) => loadMore.observe(row))
}
