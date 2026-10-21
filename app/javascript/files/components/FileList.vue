<script setup lang="ts">
import { RouterLink } from "vue-router"
import { useDropTargets } from "../dnd"
import { formatSize, formatTime } from "../format"
import { t } from "../i18n"
import type { Row } from "../rows"
import type { SelectModifiers } from "../useSelection"
import FileIcon from "./FileIcon.vue"

// selectable のときは Google ドライブと同じく、行のクリックで選び、ダブルクリック（Enter）で開く。
// 指で操作する端末ではダブルクリックしにくいので、タップで開く
const props = defineProps<{
  rows: Row[]
  empty: string
  trash?: boolean
  selectable?: boolean
  selected?: ReadonlySet<number>
  canMove?: boolean
  // 行をドラッグして、フォルダの行へ落として移せるか
  draggable?: boolean
}>()

const emit = defineEmits<{
  select: [id: number, modifiers: SelectModifiers]
  open: [row: Row]
  clear: []
  move: [row: Row]
  dragstart: [row: Row, event: DragEvent]
  dragend: []
}>()

const { over, handlers } = useDropTargets()
const dropTarget = (row: Row) =>
  props.draggable && row.folderId !== null ? handlers({ id: row.id, label: row.name }) : {}

const personColumn = props.trash ? "deleted_by" : "owner"
const timeColumn = props.trash ? "deleted_at" : "updated_at"
const rowActions = props.trash ? ["restore", "purge"] : ["download", "rename", "move", "destroy"]
const touch = typeof window.matchMedia === "function" && window.matchMedia("(pointer: coarse)").matches

const size = (row: Row) => (row.byteSize === null ? "-" : formatSize(row.byteSize))
const time = (row: Row) => (row.time === null ? "" : formatTime(row.time))
const person = (row: Row) => row.person ?? "-"
const isSelected = (row: Row) => props.selected?.has(row.id) ?? false

const click = (row: Row, event: MouseEvent) => {
  if (!props.selectable) return
  if (touch) emit("open", row)
  else emit("select", row.id, { toggle: event.ctrlKey || event.metaKey, range: event.shiftKey })
}

const open = (row: Row) => {
  if (props.selectable) emit("open", row)
}

// 行の外（見出しや一覧の下の余白）を押したら選択を解く
const clickOutside = (event: MouseEvent) => {
  if (props.selectable && !(event.target as Element).closest("tbody tr")) emit("clear")
}

const closeMenu = (event: Event) => {
  const menu = (event.target as Element).closest("details")
  if (menu) menu.open = false
}
</script>

<template>
  <div
    class="min-h-0 flex-1 overflow-auto px-3"
    @click="clickOutside"
  >
    <table
      id="file-list"
      class="w-full"
    >
      <!-- 選択中は見出しの行を操作の帯（toolbar）に差し替える。帯を別の行に出すと一覧が下へずれ、
           ダブルクリックの2回目が別の行に当たる -->
      <thead class="sticky top-0 z-1 bg-white text-xs text-slate-500">
        <tr class="h-11 border-b border-slate-200">
          <th
            v-if="$slots.toolbar"
            colspan="5"
            class="px-1 text-left font-normal"
          >
            <slot name="toolbar" />
          </th>
          <template v-else>
            <th class="px-3 text-left font-medium">
              {{ t("list.columns.name") }}
            </th>
            <th class="hidden px-3 text-left font-medium lg:table-cell">
              {{ t(`list.columns.${personColumn}`) }}
            </th>
            <th class="hidden px-3 text-left font-medium md:table-cell">
              {{ t(`list.columns.${timeColumn}`) }}
            </th>
            <th class="hidden px-3 text-right font-medium sm:table-cell">
              {{ t("list.columns.size") }}
            </th>
            <th class="w-10" />
          </template>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.id"
          :tabindex="selectable ? 0 : undefined"
          :aria-selected="selectable ? isSelected(row) : undefined"
          :draggable="draggable && !touch"
          :class="[
            'border-b border-slate-100',
            over === row.id ? 'bg-primary-50 outline-2 -outline-offset-2 outline-primary-600'
            : isSelected(row) ? 'bg-primary-100' : 'hover:bg-canvas',
            { 'cursor-default select-none focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-primary-600': selectable },
          ]"
          @click="click(row, $event)"
          @dblclick="open(row)"
          @keydown.enter="open(row)"
          @keydown.space.prevent="selectable && emit('select', row.id, { toggle: true, range: false })"
          @dragstart="emit('dragstart', row, $event)"
          @dragend="emit('dragend')"
          v-on="dropTarget(row)"
        >
          <td class="px-3 py-2.5">
            <span class="flex items-center gap-2">
              <FileIcon :folder="row.kind === 'folder'" />
              <RouterLink
                v-if="!selectable && row.folderId !== null"
                :to="{ name: 'folder', params: { id: row.folderId } }"
                class="truncate hover:text-primary-700 hover:underline"
              >{{ row.name }}</RouterLink>
              <span
                v-else-if="row.readable"
                class="truncate"
              >{{ row.name }}</span>
              <span
                v-else
                class="truncate text-slate-400"
                :title="t('list.no_access')"
              >{{ row.name }}</span>
            </span>
            <span
              v-if="row.readable"
              class="mt-0.5 block pl-7 text-xs text-slate-500 lg:hidden"
            >
              <span class="sm:hidden"><span class="inline-block min-w-[4ch]">{{ size(row) }}</span>・</span>
              <span class="md:hidden">{{ time(row) }}・</span>
              {{ person(row) }}
            </span>
          </td>
          <td class="hidden px-3 py-2.5 text-sm lg:table-cell">
            <template v-if="row.readable">
              {{ person(row) }}
            </template>
          </td>
          <td class="hidden px-3 py-2.5 text-sm md:table-cell">
            <template v-if="row.readable">
              {{ time(row) }}
            </template>
          </td>
          <td class="hidden px-3 py-2.5 text-right text-sm sm:table-cell">
            <template v-if="row.readable">
              {{ size(row) }}
            </template>
          </td>
          <td
            class="py-2.5 pr-1"
            @click.stop
            @dblclick.stop
            @keydown.stop
          >
            <!-- data-dropdown を外すと外側クリックと Esc で閉じなくなる（application.ts が拾っている） -->
            <details
              class="relative"
              data-dropdown
            >
              <summary
                class="flex cursor-pointer list-none justify-center rounded-full p-1.5 text-slate-500 hover:bg-slate-900/5 [&::-webkit-details-marker]:hidden"
                :aria-label="t('list.row_menu')"
              >
                <svg
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  class="size-5"
                  aria-hidden="true"
                >
                  <path d="M12 7a1.6 1.6 0 1 0 0-3.2A1.6 1.6 0 0 0 12 7Zm0 6.6a1.6 1.6 0 1 0 0-3.2 1.6 1.6 0 0 0 0 3.2Zm0 6.6a1.6 1.6 0 1 0 0-3.2 1.6 1.6 0 0 0 0 3.2Z" />
                </svg>
              </summary>
              <div class="absolute right-0 z-10 mt-1 w-44 rounded-xl bg-white py-1.5 text-sm shadow-lg ring-1 ring-slate-900/10">
                <template
                  v-for="action in rowActions"
                  :key="action"
                >
                  <button
                    v-if="action === 'move' && canMove"
                    type="button"
                    class="block w-full cursor-pointer px-4 py-2 text-left hover:bg-slate-100"
                    @click="closeMenu($event); emit('move', row)"
                  >
                    {{ t(`list.row_actions.${action}`) }}
                  </button>
                  <span
                    v-else
                    class="block px-4 py-2 text-slate-400"
                  >{{ t(`list.row_actions.${action}`) }}</span>
                </template>
              </div>
            </details>
          </td>
        </tr>
      </tbody>
    </table>
    <p
      v-if="rows.length === 0"
      class="py-10 text-center text-sm text-slate-500"
    >
      {{ empty }}
    </p>
  </div>
</template>
