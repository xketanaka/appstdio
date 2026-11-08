import { describe, expect, test } from "vitest"
import { clampView, cropOf, type View, zoomView } from "./avatar_cropper"

// 横長の画像（400×200）を、一辺 100px の枠で見る。拡大率 1 で 0.5 倍に縮めて出す
const view = (overrides: Partial<View> = {}): View =>
  ({ width: 400, height: 200, viewport: 100, zoom: 1, left: -50, top: 0, ...overrides })

describe("cropOf", () => {
  test("枠に入っている範囲を、画像の画素で返す", () => {
    expect(cropOf(view())).toEqual({ x: 100, y: 0, size: 200 })
  })

  test("拡大すると、範囲は狭くなる", () => {
    expect(cropOf(view({ zoom: 2, left: -150, top: -50 }))).toEqual({ x: 150, y: 50, size: 100 })
  })
})

describe("clampView", () => {
  test("画像が枠を覆うように、動かせる範囲を抑える", () => {
    expect(clampView(view({ left: 30, top: 10 }))).toMatchObject({ left: 0, top: 0 })
    expect(clampView(view({ left: -500, top: -10 }))).toMatchObject({ left: -100, top: 0 })
  })
})

describe("zoomView", () => {
  test("枠の中心を動かさずに拡大する", () => {
    const zoomed = zoomView(view(), 2)

    expect(zoomed).toMatchObject({ zoom: 2, left: -150, top: -50 })
    expect(cropOf(zoomed)).toEqual({ x: 150, y: 50, size: 100 })
  })

  test("縮めて枠からはみ出す位置は、内側に寄せる", () => {
    expect(zoomView(view({ zoom: 2, left: 0, top: 0 }), 1)).toMatchObject({ left: 0, top: 0 })
  })
})
