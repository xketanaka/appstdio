import { afterEach, beforeEach, describe, expect, test, vi } from "vitest"
import type { GroupMembers } from "./group_members"
import "./group_members"

// jsdom には IntersectionObserver が無い
vi.mock("~/components/load_more", () => ({ observeLoadMore: vi.fn() }))

const row = (id: string, name: string) => `
  <tr data-member-row="${id}">
    <td><span data-name>${name}</span><span data-email></span></td>
    <td><input type="hidden" name="group[members][${id}]" value="member">
        <input type="checkbox" name="group[members][${id}]" value="leader"></td>
    <td><button type="button" data-remove-member>外す</button></td>
  </tr>`

const candidate = (id: string, name: string) => `
  <li><label><input type="checkbox" value="${id}" data-name="${name}" data-email="${id}@example.com">${name}</label></li>`

describe("<group-members>", () => {
  let element: GroupMembers
  const rows = () => [...element.querySelectorAll<HTMLElement>("[data-member-row]")]
  const candidates = () => [...element.querySelectorAll<HTMLInputElement>("[data-candidates] input")]
  const click = (selector: string) => element.querySelector<HTMLElement>(selector)!.click()
  const respond = (html: string) => {
    vi.mocked(fetch).mockResolvedValue(new Response(html))
  }

  beforeEach(() => {
    // jsdom の dialog は showModal / close を持たないことがあるので、open 属性だけ切り替える
    HTMLDialogElement.prototype.showModal = function () {
      this.setAttribute("open", "")
    }
    HTMLDialogElement.prototype.close = function () {
      this.removeAttribute("open")
    }
    vi.stubGlobal("fetch", vi.fn())
    respond(candidate("1", "佐藤さん") + candidate("2", "山田さん") + candidate("3", "田中さん"))

    document.body.innerHTML = `
      <form>
        <group-members data-candidates-url="/management/groups/9/member_candidates"
                       data-count-text="所属メンバー（%{count}人）" data-load-error="読み込めませんでした。">
          <h3 data-count>所属メンバー（1人）</h3>
          <button type="button" data-open-dialog>メンバーを追加</button>
          <p data-empty hidden>いません</p>
          <table><tbody data-rows>${row("1", "佐藤さん")}</tbody></table>
          <template data-row-template>${row("", "")}</template>
          <dialog>
            <input type="search" data-search>
            <ul data-candidates></ul>
            <button type="button" data-close-dialog>キャンセル</button>
            <button type="button" data-add-members>追加する</button>
          </dialog>
        </group-members>
      </form>`
    element = document.querySelector("group-members")!
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.useRealTimers()
  })

  test("ダイアログを開くと候補を読み込み、すでにいる人は選べないようにする", async () => {
    click("[data-open-dialog]")
    await vi.waitFor(() => expect(candidates()).toHaveLength(3))

    expect(element.querySelector("dialog")!.open).toBe(true)
    expect(fetch).toHaveBeenCalledWith(new URL("/management/groups/9/member_candidates", window.location.href),
      expect.anything())
    expect(candidates().map((input) => [input.value, input.disabled, input.checked]))
      .toEqual([["1", true, true], ["2", false, false], ["3", false, false]])
  })

  test("選んだ人を行として足し、人数を数え直す", async () => {
    click("[data-open-dialog]")
    await vi.waitFor(() => expect(candidates()).toHaveLength(3))
    candidates()[1].checked = true
    candidates()[2].checked = true
    click("[data-add-members]")

    expect(element.querySelector("dialog")!.open).toBe(false)
    expect(rows().map((tr) => [tr.dataset.memberRow, tr.querySelector("[data-name]")!.textContent]))
      .toEqual([["1", "佐藤さん"], ["2", "山田さん"], ["3", "田中さん"]])
    expect([...rows()[2].querySelectorAll("input")].map((input) => input.name))
      .toEqual(["group[members][3]", "group[members][3]"])
    expect(element.querySelector("[data-count]")!.textContent).toBe("所属メンバー（3人）")
  })

  test("行を外すと、人数を数え直し、いなくなれば空の案内を出す", () => {
    click("[data-remove-member]")

    expect(rows()).toHaveLength(0)
    expect(element.querySelector("[data-count]")!.textContent).toBe("所属メンバー（0人）")
    expect(element.querySelector<HTMLElement>("[data-empty]")!.hidden).toBe(false)
    expect(element.querySelector("table")!.hidden).toBe(true)
  })

  test("打つと少し待ってから探し、Enter ではフォームを送らずにすぐ探す", async () => {
    click("[data-open-dialog]")
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1))
    vi.useFakeTimers()
    const search = element.querySelector<HTMLInputElement>("[data-search]")!

    search.value = "山田"
    search.dispatchEvent(new Event("input"))
    expect(fetch).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(300)
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(String(vi.mocked(fetch).mock.calls[1][0])).toContain("q=%E5%B1%B1%E7%94%B0")

    const enter = new KeyboardEvent("keydown", { key: "Enter", cancelable: true })
    search.dispatchEvent(enter)
    expect(enter.defaultPrevented).toBe(true)
    expect(fetch).toHaveBeenCalledTimes(3)
  })

  test("後から届いた古い検索の結果で上書きしない", async () => {
    let resolveFirst!: (response: Response) => void
    vi.mocked(fetch)
      .mockReturnValueOnce(new Promise((resolve) => { resolveFirst = resolve }))
      .mockResolvedValueOnce(new Response(candidate("2", "山田さん")))
    click("[data-open-dialog]")
    const search = element.querySelector<HTMLInputElement>("[data-search]")!
    search.value = "山田"
    search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }))
    await vi.waitFor(() => expect(candidates()).toHaveLength(1))

    resolveFirst(new Response(candidate("1", "佐藤さん") + candidate("3", "田中さん")))
    await new Promise((resolve) => setTimeout(resolve))
    expect(candidates().map((input) => input.value)).toEqual(["2"])
  })

  test("読み込めなかったときは候補の欄に知らせる", async () => {
    vi.mocked(fetch).mockResolvedValue(new Response("", { status: 500 }))
    click("[data-open-dialog]")

    await vi.waitFor(() => expect(element.querySelector("[data-candidates] [role=alert]")?.textContent)
      .toBe("読み込めませんでした。"))
  })
})
