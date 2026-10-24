<script setup lang="ts">
import { t } from "../i18n"

// 選択中に、一覧の見出しの行の代わりに出す帯（FileList の toolbar の差し込み口に入れる）。
// 選んだものへの操作のボタンは、差し込み口（slot）に並べる
defineProps<{ count: number }>()
const emit = defineEmits<{ clear: [] }>()
</script>

<template>
  <div
    role="toolbar"
    :aria-label="t('selection.count', { count })"
    class="flex items-center gap-2 text-sm text-slate-800"
  >
    <button
      type="button"
      class="cursor-pointer rounded-full p-1.5 text-slate-600 hover:bg-slate-900/5"
      :aria-label="t('selection.clear')"
      @click="emit('clear')"
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
    <span class="mr-2">{{ t("selection.count", { count }) }}</span>
    <slot />
  </div>
</template>
