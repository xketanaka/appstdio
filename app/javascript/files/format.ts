const pad = (n: number) => String(n).padStart(2, "0")

// FormatUtils#time_to_s と同じ形
export function formatTime(iso: string): string {
  const d = new Date(iso)
  return `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

const UNITS = ["KB", "MB", "GB", "TB", "PB", "EB"]

// number_to_human_size と同じ形（1024 区切り、有効数字3桁）
export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} Bytes`

  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), UNITS.length)
  const value = Number((bytes / 1024 ** exponent).toPrecision(3))
  return `${value} ${UNITS[exponent - 1]}`
}
