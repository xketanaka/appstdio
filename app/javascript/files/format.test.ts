import { describe, expect, test } from "vitest"
import { formatSize, formatTime } from "./format"

describe("formatSize", () => {
  test.each([
    [0, "0 Bytes"],
    [1023, "1023 Bytes"],
    [1024, "1 KB"],
    [25_088, "24.5 KB"],
    [1024 ** 2 * 3.333, "3.33 MB"],
    [1024 ** 3 * 12.5, "12.5 GB"],
    [1024 ** 4 * 2, "2 TB"],
    [1024 ** 5 * 3, "3 PB"],
  ])("%d は %s（number_to_human_size と同じ）", (bytes, expected) => {
    expect(formatSize(bytes)).toBe(expected)
  })
})

describe("formatTime", () => {
  test("年/月/日 時:分 にする", () => {
    expect(formatTime(new Date(2026, 0, 5, 9, 3).toISOString())).toBe("2026/01/05 09:03")
  })
})
