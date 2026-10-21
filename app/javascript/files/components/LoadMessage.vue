<script setup lang="ts">
import { t } from "../i18n"
import type { LoadStatus } from "../useLoad"

defineProps<{ status: LoadStatus }>()
</script>

<template>
  <p
    v-if="status === 'not_found' || status === 'error'"
    role="alert"
    class="px-6 py-10 text-center text-sm text-slate-500"
  >
    {{ t(`load.${status}`) }}
  </p>
</template>
