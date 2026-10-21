<script setup lang="ts">
import { RouterLink } from "vue-router"
import { formatSize, formatTime } from "../format"
import { t } from "../i18n"
import type { Row } from "../rows"
import FileIcon from "./FileIcon.vue"

const props = defineProps<{ rows: Row[], empty: string, trash?: boolean }>()

const personColumn = props.trash ? "deleted_by" : "owner"
const timeColumn = props.trash ? "deleted_at" : "updated_at"
const rowActions = props.trash ? ["restore", "purge"] : ["download", "rename", "destroy"]

const size = (row: Row) => (row.byteSize === null ? "-" : formatSize(row.byteSize))
const time = (row: Row) => (row.time === null ? "" : formatTime(row.time))
const person = (row: Row) => row.person ?? "-"
</script>

<template>
  <div class="min-h-0 flex-1 overflow-auto px-3">
    <table
      id="file-list"
      class="w-full"
    >
      <thead class="sticky top-0 bg-white text-xs text-slate-500">
        <tr class="border-b border-slate-200">
          <th class="px-3 py-2.5 text-left font-medium">
            {{ t("list.columns.name") }}
          </th>
          <th class="hidden px-3 py-2.5 text-left font-medium lg:table-cell">
            {{ t(`list.columns.${personColumn}`) }}
          </th>
          <th class="hidden px-3 py-2.5 text-left font-medium md:table-cell">
            {{ t(`list.columns.${timeColumn}`) }}
          </th>
          <th class="hidden px-3 py-2.5 text-right font-medium sm:table-cell">
            {{ t("list.columns.size") }}
          </th>
          <th class="w-10" />
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.id"
          class="border-b border-slate-100 hover:bg-canvas"
        >
          <td class="px-3 py-2.5">
            <span class="flex items-center gap-2">
              <FileIcon :folder="row.kind === 'folder'" />
              <RouterLink
                v-if="row.folderId !== null"
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
          <td class="py-2.5 pr-1">
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
                <span
                  v-for="action in rowActions"
                  :key="action"
                  class="block px-4 py-2 text-slate-400"
                >{{ t(`list.row_actions.${action}`) }}</span>
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
