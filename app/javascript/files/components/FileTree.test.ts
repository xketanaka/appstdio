import { testRouter } from "../testing"
import { mount } from "@vue/test-utils"
import { beforeEach, expect, test } from "vitest"
import { nextTick } from "vue"
import { showSection, state } from "../store"
import FileTree from "./FileTree.vue"

beforeEach(() => {
  state.openSections.clear()
  state.tree = {
    shared_drive: [{ id: 2, name: "営業", readable: true }, { id: 3, name: "人事", readable: false }],
    my_drive: [{ id: 9, name: "下書き", readable: true }],
  }
})

const render = async () => {
  const router = testRouter()
  await router.push("/shared_drive")
  return mount(FileTree, { global: { plugins: [router] }, attachTo: document.body })
}

test("開いている区分を示し、開けないフォルダはリンクにしない", async () => {
  showSection("shared_drive", "組織共有ドライブ")
  const wrapper = await render()

  expect(wrapper.find("[aria-current=page]").text()).toBe("組織共有ドライブ")
  expect(wrapper.findAll("details")[0].element.open).toBe(true)
  expect(wrapper.find("a[href='/folders/2']").exists()).toBe(true)
  expect(wrapper.find("a[href='/folders/3']").exists()).toBe(false)
})

test("利用者が開いた区分は、別の区分へ移っても閉じない", async () => {
  showSection("shared_drive", "組織共有ドライブ")
  const wrapper = await render()
  const myDrive = wrapper.findAll("details")[1].element

  myDrive.open = true
  myDrive.dispatchEvent(new Event("toggle"))
  showSection("trash", "ゴミ箱")
  await nextTick()

  expect(wrapper.findAll("details").map((details) => details.element.open)).toEqual([true, true])
  expect(wrapper.find("[aria-current=page]").text()).toBe("ゴミ箱")
})
