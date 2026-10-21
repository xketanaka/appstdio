export type Messages = { [key: string]: string | Messages }

let messages: Messages = {}

export function setMessages(value: Messages) {
  messages = value
}

// config/locales の files_app 以下を引く。%{name} の埋め込みは Rails と同じ書き方
export function t(key: string, params: Record<string, string | number> = {}): string {
  const value = key.split(".").reduce<string | Messages | undefined>(
    (node, part) => (typeof node === "object" ? node[part] : undefined),
    messages,
  )
  if (typeof value !== "string") {
    // Rails の raise_on_missing_translations と同じく、開発中は漏れを例外にする
    if (import.meta.env.PROD) return key
    throw new Error(`Translation missing: files_app.${key}`)
  }
  return value.replace(/%\{(\w+)\}/g, (match, name: string) => String(params[name] ?? match))
}
