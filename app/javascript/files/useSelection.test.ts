import { describe, expect, test } from "vitest"
import { nextTick, ref } from "vue"
import { useSelection } from "./useSelection"

const plain = { toggle: false, range: false }
const toggle = { toggle: true, range: false }
const range = { toggle: false, range: true }

const setup = () => {
  const ids = ref([1, 2, 3, 4, 5])
  return { ids, ...useSelection(() => ids.value) }
}

describe("useSelection", () => {
  test("クリックはその1件だけを選ぶ", () => {
    const { selected, select } = setup()
    select(2, plain)
    select(4, plain)

    expect([...selected]).toEqual([4])
  })

  test("Ctrl は1件ずつ足し引きする", () => {
    const { selected, select } = setup()
    select(2, plain)
    select(4, toggle)
    select(2, toggle)

    expect([...selected]).toEqual([4])
  })

  test("Shift は起点から範囲を選び直す。起点は動かない", () => {
    const { selected, select } = setup()
    select(2, plain)
    select(4, range)
    expect([...selected].sort()).toEqual([2, 3, 4])

    select(1, range)
    expect([...selected].sort()).toEqual([1, 2])
  })

  test("Ctrl と Shift を一緒に押すと、今の選択に範囲を足す", () => {
    const { selected, select } = setup()
    select(5, plain)
    select(1, toggle)
    select(3, { toggle: true, range: true })

    expect([...selected].sort()).toEqual([1, 2, 3, 5])
  })

  test("一覧から消えたものは選択から外れる", async () => {
    const { ids, selected, select } = setup()
    select(2, plain)
    select(3, toggle)
    ids.value = [1, 3]
    await nextTick()

    expect([...selected]).toEqual([3])
  })
})
