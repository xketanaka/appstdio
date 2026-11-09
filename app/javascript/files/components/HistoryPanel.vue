<script setup lang="ts">
import { ref, watch } from "vue"
import { t } from "../i18n"
import { state } from "../store"
import ActivityList from "./ActivityList.vue"
import VersionList from "./VersionList.vue"

// 履歴。右から出るパネル（dialog）。行のメニューやフォルダの「履歴」で state.historyOf が入ると開く。
// 操作履歴と版をタブで出し分ける。フォルダには版が無いので、操作履歴だけ
const dialog = ref<HTMLDialogElement | null>(null)
const tab = ref<"activities" | "versions">("activities")

watch(() => state.historyOf, (target) => {
  tab.value = "activities"
  if (target) dialog.value?.showModal()
})

const close = () => {
  dialog.value?.close()
  state.historyOf = null
}
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="history-title"
    class="m-0 ml-auto h-dvh max-h-dvh w-full max-w-md bg-white text-slate-800 shadow-xl backdrop:bg-slate-900/40"
    @close="state.historyOf = null"
  >
    <div
      v-if="state.historyOf"
      class="flex h-full flex-col"
    >
      <header class="flex shrink-0 items-center justify-between gap-2 px-6 pt-5 pb-3">
        <h2
          id="history-title"
          class="truncate text-lg font-medium"
        >
          {{ t("history.title", { name: state.historyOf.name }) }}
        </h2>
        <button
          type="button"
          class="cursor-pointer rounded-full p-1.5 text-slate-600 hover:bg-slate-900/5"
          :aria-label="t('history.close')"
          @click="close"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="size-5"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              d="M6 6l12 12M18 6L6 18"
            />
          </svg>
        </button>
      </header>

      <div
        v-if="state.historyOf.kind === 'file'"
        role="tablist"
        class="flex shrink-0 gap-1 border-b border-slate-200 px-6"
      >
        <button
          v-for="key in ['activities', 'versions'] as const"
          :id="`history-tab-${key}`"
          :key="key"
          type="button"
          role="tab"
          :aria-selected="tab === key"
          aria-controls="history-tabpanel"
          :class="[
            '-mb-px cursor-pointer border-b-2 px-3 py-2 text-sm',
            tab === key ? 'border-primary-600 font-medium text-primary-700' : 'border-transparent text-slate-600 hover:text-slate-800',
          ]"
          @click="tab = key"
        >
          {{ t(`history.tabs.${key}`) }}
        </button>
      </div>

      <div
        id="history-tabpanel"
        :role="state.historyOf.kind === 'file' ? 'tabpanel' : undefined"
        :aria-labelledby="state.historyOf.kind === 'file' ? `history-tab-${tab}` : undefined"
        class="min-h-0 flex-1 overflow-y-auto px-3 pb-4"
      >
        <VersionList
          v-if="tab === 'versions'"
          :file-id="state.historyOf.id"
        />
        <ActivityList
          v-else
          :key="state.historyOf.id"
          :node-id="state.historyOf.id"
        />
      </div>
    </div>
  </dialog>
</template>
