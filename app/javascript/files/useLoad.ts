import { ref, shallowRef, watch, type WatchSource } from "vue"
import { NotFoundError } from "./api"
import { state } from "./store"

export type LoadStatus = "loading" | "ready" | "not_found" | "error"

// 画面の中身を API から読む。source が変わったとき（別のフォルダへ移ったとき）と、
// 特権モードを切り替えたとき（見える範囲が変わる）に読み直す
export function useLoad<T>(load: () => Promise<T>, source: WatchSource, onLoaded: (value: T) => void = () => {}) {
  const data = shallowRef<T | null>(null)
  const status = ref<LoadStatus>("loading")
  let latest = 0

  const run = async () => {
    // 続けて移動したとき、先に出した要求の応答が後から届いて上書きしないようにする
    const ticket = ++latest
    try {
      const value = await load()
      if (ticket !== latest) return
      data.value = value
      status.value = "ready"
      onLoaded(value)
    } catch (error) {
      if (ticket !== latest) return
      status.value = error instanceof NotFoundError ? "not_found" : "error"
      if (!(error instanceof NotFoundError)) console.error(error)
    }
  }

  watch([source, () => state.privileged], run, { immediate: true })

  return { data, status }
}
