import "../testing"
import { mount } from "@vue/test-utils"
import { beforeEach, expect, test } from "vitest"
import { state } from "../store"
import StorageMeter from "./StorageMeter.vue"

const GB = 1024 ** 3

const render = (used: number) => {
  state.tree = { shared_drive: null, my_drive: null, storage: { used_bytes: used, limit_bytes: 10 * GB } }
  return mount(StorageMeter)
}

beforeEach(() => {
  state.tree = null
})

test("上限と使用量を出す", () => {
  const wrapper = render(2.5 * GB)

  expect(wrapper.text()).toBe("10 GB 中 2.5 GB を使用")
  expect(wrapper.find("[role=meter]").attributes("aria-valuetext")).toBe("10 GB 中 2.5 GB を使用")
})

test("9割を超えたら残りわずかであることを、上限に達したらアップロードできないことを添える", () => {
  expect(render(9.2 * GB).text()).toContain("容量が残りわずかです")
  expect(render(10 * GB).text()).toContain("容量の上限に達したため、アップロードできません")
})

test("ツリーを読み込むまでは何も出さない", () => {
  expect(mount(StorageMeter).find("[role=meter]").exists()).toBe(false)
})
