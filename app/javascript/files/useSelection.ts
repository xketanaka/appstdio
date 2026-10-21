import { reactive, watch } from "vue"

export type SelectModifiers = { toggle: boolean, range: boolean }

// 一覧の選択。Google ドライブと同じく、クリックで1件、Ctrl（Mac は ⌘）で1件ずつ足し引き、
// Shift で起点から範囲を選ぶ。ids は一覧に並んでいる順
export function useSelection(ids: () => number[]) {
  const selected = reactive(new Set<number>())
  let anchor: number | null = null

  const select = (id: number, { toggle, range }: SelectModifiers) => {
    const order = ids()
    if (range && anchor !== null && order.includes(anchor)) {
      const [from, to] = [order.indexOf(anchor), order.indexOf(id)].sort((a, b) => a - b)
      if (!toggle) selected.clear()
      order.slice(from, to + 1).forEach((each) => selected.add(each))
      return
    }
    if (toggle) {
      if (selected.has(id)) selected.delete(id)
      else selected.add(id)
    } else {
      selected.clear()
      selected.add(id)
    }
    anchor = id
  }

  const clear = () => {
    selected.clear()
    anchor = null
  }

  // 読み直して一覧から消えたもの（移動したものなど）は、選択からも外す
  watch(ids, (current) => {
    selected.forEach((id) => {
      if (!current.includes(id)) selected.delete(id)
    })
  })

  return { selected, select, clear }
}
