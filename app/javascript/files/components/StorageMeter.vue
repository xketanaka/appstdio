<script setup lang="ts">
import { computed } from "vue"
import { formatSize } from "../format"
import { t } from "../i18n"
import { state } from "../store"

// 組織全体の使用量。9割を超えたら注意の色、上限に達したら赤で、理由を添える
const storage = computed(() => state.tree?.storage)
const ratio = computed(() => (storage.value ? storage.value.used_bytes / storage.value.limit_bytes : 0))
const level = computed(() => (ratio.value >= 1 ? "full" : ratio.value >= 0.9 ? "nearly_full" : null))
</script>

<template>
  <div
    v-if="storage"
    class="mt-4 border-t border-slate-200 px-4 pt-3"
  >
    <div
      role="meter"
      :aria-label="t('storage.label')"
      :aria-valuenow="storage.used_bytes"
      aria-valuemin="0"
      :aria-valuemax="storage.limit_bytes"
      :aria-valuetext="t('storage.usage', { used: formatSize(storage.used_bytes), limit: formatSize(storage.limit_bytes) })"
      class="h-1.5 overflow-hidden rounded-full bg-slate-200"
    >
      <div
        :class="['h-full rounded-full', level === 'full' ? 'bg-red-600' : level ? 'bg-amber-500' : 'bg-primary-600']"
        :style="{ width: `${Math.min(ratio, 1) * 100}%` }"
      />
    </div>
    <p class="mt-1.5 text-xs text-slate-600">
      {{ t("storage.usage", { used: formatSize(storage.used_bytes), limit: formatSize(storage.limit_bytes) }) }}
    </p>
    <p
      v-if="level"
      :class="['mt-1 text-xs', level === 'full' ? 'text-red-700' : 'text-amber-800']"
    >
      {{ t(`storage.${level}`) }}
    </p>
  </div>
</template>
