// アバターにする画像を選び、丸の中に入れる範囲を調整して送る。切り抜きと縮小はサーバで行い、
// ここは切り抜く正方形（画像の画素での x / y / size）を hidden の欄に入れるだけ。
//
// <avatar-cropper>
//   <form>
//     <input type="file" data-file>
//     <input type="hidden" data-crop="x"> <input type="hidden" data-crop="y"> <input type="hidden" data-crop="size">
//     <dialog> <div data-viewport><img data-image></div> <input type="range" data-zoom>
//              <button data-cancel> <button type="submit"> </dialog>
//   </form>
// </avatar-cropper>
//
// 枠（viewport）いっぱいの正方形が切り抜く範囲。画像は枠を必ず覆うように、動かせる範囲と縮められる大きさを抑える

const KEY_STEP = 10

export type View = {
  // 画像の大きさ（EXIF の向きを直した後。ブラウザの naturalWidth / naturalHeight も向きを直した値）
  width: number
  height: number
  // 枠の一辺（画面の px）
  viewport: number
  // 拡大率。1 で画像の短い辺が枠にちょうど収まる
  zoom: number
  // 枠の左上から見た画像の左上（画面の px）。画像が枠を覆うので 0 以下
  left: number
  top: number
}

export const scaleOf = (view: View) => (view.viewport / Math.min(view.width, view.height)) * view.zoom

// 画像が枠からはみ出さず、枠を覆う位置に寄せる
export const clampView = (view: View): View => {
  const scale = scaleOf(view)
  const clamp = (value: number, min: number) => Math.min(0, Math.max(min, value))
  return {
    ...view,
    left: clamp(view.left, view.viewport - view.width * scale),
    top: clamp(view.top, view.viewport - view.height * scale),
  }
}

// 枠の中心を動かさずに拡大率を変える
export const zoomView = (view: View, zoom: number): View => {
  const center = view.viewport / 2
  const ratio = zoom / view.zoom
  return clampView({
    ...view,
    zoom,
    left: center - (center - view.left) * ratio,
    top: center - (center - view.top) * ratio,
  })
}

// 枠に入っている範囲を、画像の画素で表す
export const cropOf = (view: View) => {
  const scale = scaleOf(view)
  const size = Math.min(Math.round(view.viewport / scale), view.width, view.height)
  return {
    x: Math.max(0, Math.min(Math.round(-view.left / scale), view.width - size)),
    y: Math.max(0, Math.min(Math.round(-view.top / scale), view.height - size)),
    size,
  }
}

export class AvatarCropper extends HTMLElement {
  #view?: View
  #objectUrl?: string
  #drag?: { pointerId: number, x: number, y: number }

  connectedCallback() {
    if (this.dataset.ready) return
    this.dataset.ready = "true"

    this.#file().addEventListener("change", () => this.#open())
    this.querySelector("[data-cancel]")!.addEventListener("click", () => this.#dialog().close())
    // Esc で閉じたときも、選んだファイルを外す（そのまま別の操作で送られないように）
    this.#dialog().addEventListener("close", () => {
      if (this.#dialog().returnValue !== "submit") this.#file().value = ""
    })
    this.querySelector("form")!.addEventListener("submit", () => this.#fillCrop())

    const viewport = this.#viewport()
    viewport.addEventListener("pointerdown", (event) => {
      viewport.setPointerCapture(event.pointerId)
      this.#drag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY }
    })
    viewport.addEventListener("pointermove", (event) => {
      if (!this.#drag || this.#drag.pointerId !== event.pointerId) return
      this.#move(event.clientX - this.#drag.x, event.clientY - this.#drag.y)
      this.#drag = { ...this.#drag, x: event.clientX, y: event.clientY }
    })
    const endDrag = () => (this.#drag = undefined)
    viewport.addEventListener("pointerup", endDrag)
    viewport.addEventListener("pointercancel", endDrag)
    viewport.addEventListener("keydown", (event) => {
      const moves: Record<string, [number, number]> = {
        ArrowLeft: [KEY_STEP, 0], ArrowRight: [-KEY_STEP, 0], ArrowUp: [0, KEY_STEP], ArrowDown: [0, -KEY_STEP],
      }
      const move = moves[event.key]
      if (!move) return
      event.preventDefault()
      this.#move(...move)
    })

    this.#zoom().addEventListener("input", () => {
      if (!this.#view) return
      this.#view = zoomView(this.#view, Number(this.#zoom().value))
      this.#render()
    })
  }

  disconnectedCallback() {
    if (this.#objectUrl) URL.revokeObjectURL(this.#objectUrl)
  }

  async #open() {
    const file = this.#file().files?.[0]
    if (!file) return

    if (this.#objectUrl) URL.revokeObjectURL(this.#objectUrl)
    this.#objectUrl = URL.createObjectURL(file)
    const image = this.#image()
    // 大きさを合わせるまで、前の画像の大きさのまま出さない
    image.style.visibility = "hidden"
    image.src = this.#objectUrl
    this.#zoom().value = "1"
    this.#dialog().returnValue = ""
    this.#dialog().showModal()
    try {
      await image.decode()
    } catch {
      // ブラウザで表示できない画像は位置を調整できない。そのまま送って、サーバの検証に任せる
      this.#view = undefined
      return
    }

    const viewport = this.#viewport().clientWidth
    const { naturalWidth: width, naturalHeight: height } = image
    const scale = viewport / Math.min(width, height)
    // 初めは中央に置く
    this.#view = { width, height, viewport, zoom: 1, left: (viewport - width * scale) / 2, top: (viewport - height * scale) / 2 }
    this.#render()
  }

  #move(dx: number, dy: number) {
    if (!this.#view) return
    this.#view = clampView({ ...this.#view, left: this.#view.left + dx, top: this.#view.top + dy })
    this.#render()
  }

  #render() {
    if (!this.#view) return
    const scale = scaleOf(this.#view)
    const image = this.#image()
    image.style.width = `${this.#view.width * scale}px`
    image.style.height = `${this.#view.height * scale}px`
    image.style.transform = `translate(${this.#view.left}px, ${this.#view.top}px)`
    image.style.visibility = ""
  }

  #fillCrop() {
    this.#dialog().returnValue = "submit"
    const crop = this.#view ? cropOf(this.#view) : undefined
    for (const field of this.querySelectorAll<HTMLInputElement>("input[data-crop]")) {
      field.value = crop ? String(crop[field.dataset.crop as keyof typeof crop]) : ""
    }
  }

  #file() {
    return this.querySelector<HTMLInputElement>("[data-file]")!
  }

  #dialog() {
    return this.querySelector("dialog")!
  }

  #viewport() {
    return this.querySelector<HTMLElement>("[data-viewport]")!
  }

  #image() {
    return this.querySelector<HTMLImageElement>("[data-image]")!
  }

  #zoom() {
    return this.querySelector<HTMLInputElement>("[data-zoom]")!
  }
}

if (!customElements.get("avatar-cropper")) customElements.define("avatar-cropper", AvatarCropper)
