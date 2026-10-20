<script setup lang="ts">
import { api } from "../api"
import { t } from "../i18n"
import { config, reloadTree, state } from "../store"

const toggle = async () => {
  await (state.privileged ? api.leavePrivilegedMode() : api.enterPrivilegedMode())
  state.privileged = !state.privileged
  await reloadTree()
}
</script>

<template>
  <div
    v-if="config.admin_or_owner"
    class="mt-4 border-t border-slate-200 px-4 pt-3"
  >
    <button
      type="button"
      role="switch"
      :aria-checked="state.privileged"
      class="flex w-full cursor-pointer items-center justify-between gap-3 text-sm text-slate-700"
      @click="toggle"
    >
      <span>{{ t("privileged_mode.label") }}</span>
      <span :class="['relative inline-flex h-5 w-9 shrink-0 rounded-full transition-colors', state.privileged ? 'bg-amber-500' : 'bg-slate-300']">
        <span :class="['absolute top-0.5 left-0.5 size-4 rounded-full bg-white shadow transition-transform', { 'translate-x-4': state.privileged }]" />
      </span>
    </button>
    <p class="mt-1 text-xs text-slate-500">
      {{ t("privileged_mode.description") }}
    </p>
  </div>
</template>
