<script setup lang="ts">
import { t } from "../i18n"
import { state } from "../store"

// 画面の下に一時的に出す知らせ。数秒で消える（store の notify）
</script>

<template>
  <div
    class="pointer-events-none fixed inset-x-0 bottom-4 z-30 flex justify-center px-4 sm:justify-start sm:px-6"
    :role="state.notice?.error ? 'alert' : 'status'"
  >
    <div
      v-if="state.notice"
      class="pointer-events-auto flex max-w-xl items-center gap-3 rounded-xl px-4 py-3 text-sm text-white shadow-lg"
      :class="state.notice.error ? 'bg-red-700' : 'bg-slate-800'"
    >
      <span>{{ state.notice.message }}</span>
      <button
        v-if="state.notice.action"
        type="button"
        class="shrink-0 cursor-pointer rounded-full px-2 py-1 font-medium text-primary-200 hover:bg-white/10"
        @click="state.notice.action.run"
      >
        {{ state.notice.action.label }}
      </button>
      <button
        type="button"
        class="shrink-0 cursor-pointer rounded-full p-1 text-white/80 hover:bg-white/10"
        :aria-label="t('notice.close')"
        @click="state.notice = null"
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
    </div>
  </div>
</template>
