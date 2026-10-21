<script setup lang="ts">
import { computed } from "vue"
import { formatSize } from "../format"
import { t } from "../i18n"
import { clearFinished, uploads, type Upload } from "../uploads"

// 画面の右下に出すアップロードの一覧。画面の左下の知らせ（NoticeBar）と重ならないよう右に置く
const done = computed(() => uploads.filter((upload) => upload.status === "done").length)
const busy = computed(() => uploads.some((upload) => upload.status !== "done" && upload.status !== "error"))
const percent = (upload: Upload) => (upload.size === 0 ? 100 : Math.floor((upload.loaded / upload.size) * 100))
</script>

<template>
  <section
    v-if="uploads.length > 0"
    :aria-label="t('upload.title')"
    class="fixed right-4 bottom-4 z-30 w-[calc(100%-2rem)] max-w-sm overflow-hidden rounded-2xl bg-white text-sm shadow-lg ring-1 ring-slate-900/10"
  >
    <header class="flex items-center justify-between gap-2 bg-canvas px-4 py-2.5">
      <h2 class="font-medium">
        {{ t("upload.summary", { done, total: uploads.length }) }}
      </h2>
      <button
        type="button"
        class="cursor-pointer rounded-full p-1.5 text-slate-600 hover:bg-slate-900/5 disabled:invisible"
        :aria-label="t('upload.close')"
        :disabled="busy"
        @click="clearFinished"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          class="size-4"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            d="M6 6l12 12M18 6L6 18"
          />
        </svg>
      </button>
    </header>
    <ul class="max-h-64 overflow-y-auto">
      <li
        v-for="upload in uploads"
        :key="upload.id"
        class="border-t border-slate-100 px-4 py-2.5"
      >
        <div class="flex items-center justify-between gap-3">
          <span class="truncate">{{ upload.name }}</span>
          <span class="shrink-0 text-xs text-slate-500">{{ formatSize(upload.size) }}</span>
        </div>
        <p
          v-if="upload.status === 'error'"
          role="alert"
          class="mt-0.5 text-xs text-red-700"
        >
          {{ upload.message }}
        </p>
        <p
          v-else-if="upload.status === 'done'"
          class="mt-0.5 text-xs text-slate-500"
        >
          {{ t("upload.done", { destination: upload.destination }) }}
        </p>
        <p
          v-else-if="upload.status !== 'uploading'"
          class="mt-0.5 text-xs text-slate-500"
        >
          {{ t(`upload.${upload.status}`) }}
        </p>
        <div
          v-else
          role="progressbar"
          :aria-valuenow="percent(upload)"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-label="upload.name"
          class="mt-1.5 h-1 overflow-hidden rounded-full bg-slate-100"
        >
          <div
            class="h-full rounded-full bg-primary-600 transition-[width]"
            :style="{ width: `${percent(upload)}%` }"
          />
        </div>
      </li>
    </ul>
  </section>
</template>
