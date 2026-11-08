import { testRouter } from "../testing"
import { flushPromises, mount } from "@vue/test-utils"
import { beforeEach, expect, test } from "vitest"
import { state } from "../store"
import SearchBar from "./SearchBar.vue"

beforeEach(() => {
  state.searchOrigin = { key: "12", label: "営業" }
})

const render = async (path = "/folders/12") => {
  const router = testRouter()
  await router.push(path)
  const wrapper = mount(SearchBar, { global: { plugins: [router] } })
  return { wrapper, router }
}

test("開いている場所の中から探す", async () => {
  const { wrapper, router } = await render()

  expect(wrapper.find("summary").text()).toBe("営業 内")
  await wrapper.find("input").setValue(" 見積 ")
  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(router.currentRoute.value.query).toEqual({ q: "見積", in: "12" })
})

test("範囲をすべての場所に広げて探し、結果の画面から元の場所に戻せる", async () => {
  const { wrapper, router } = await render()
  await wrapper.find("input").setValue("見積")
  const choose = async (label: string) => {
    await wrapper.findAll("[role=menuitemradio]").find((item) => item.text() === label)!.trigger("click")
    await flushPromises()
  }

  await choose("すべての場所")
  expect(router.currentRoute.value.name, "検索欄で Enter を押すまでは探さない").toBe("folder")
  await wrapper.find("form").trigger("submit")
  await flushPromises()
  expect(router.currentRoute.value.query).toEqual({ q: "見積", in: "12", all: "1" })
  expect(wrapper.find("summary").text()).toBe("すべての場所")

  await choose("営業 内")
  expect(router.currentRoute.value.query).toEqual({ q: "見積", in: "12" })
  expect(wrapper.find("summary").text()).toBe("営業 内")
})

test("結果の画面を開くと、URL の言葉と範囲を欄と印に映し、他の画面へ移ると空に戻す", async () => {
  const { wrapper, router } = await render("/search?q=見積&in=12&all=1")

  expect((wrapper.find("input").element as HTMLInputElement).value).toBe("見積")
  expect(wrapper.find("summary").text()).toBe("すべての場所")

  await router.push("/trash")
  await flushPromises()
  expect((wrapper.find("input").element as HTMLInputElement).value).toBe("")
  expect(wrapper.find("summary").text()).toBe("営業 内")
})

test("空のままでは探さない", async () => {
  const { wrapper, router } = await render()

  await wrapper.find("form").trigger("submit")
  await flushPromises()

  expect(router.currentRoute.value.name).toBe("folder")
})
