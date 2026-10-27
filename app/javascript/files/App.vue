<script setup lang="ts">
import { onMounted, ref, watch } from "vue"
import { RouterView, useRoute, useRouter } from "vue-router"
import { api } from "./api"
import FileTree from "./components/FileTree.vue"
import NoticeBar from "./components/NoticeBar.vue"
import PrivilegedModeSwitch from "./components/PrivilegedModeSwitch.vue"
import UploadPanel from "./components/UploadPanel.vue"
import VersionsPanel from "./components/VersionsPanel.vue"
import { t } from "./i18n"
import { reloadTree, state } from "./store"

const route = useRoute()
const router = useRouter()
const mobilePane = ref<HTMLDetailsElement | null>(null)

onMounted(reloadTree)

// スマホでは左ペインを折りたたみで出している。移動したら閉じて、本文を見せる
watch(() => route.fullPath, () => {
  if (mobilePane.value) mobilePane.value.open = false
})

// 特権でしか開けない場所にいた場合に開けなくならないよう、終えたらドライブのルートへ戻る
const leavePrivilegedMode = async () => {
  await api.leavePrivilegedMode()
  // 先に移る。今いる場所を読み直すと、特権が無いため「見つからない」が一瞬出る
  await router.push({ name: "shared_drive" })
  state.privileged = false
  await reloadTree()
}
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <div
      v-if="state.privileged"
      role="status"
      class="mx-2 mb-2 flex shrink-0 items-center justify-between gap-4 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2 text-sm text-amber-900 md:mx-4"
    >
      <span>{{ t("privileged_mode.active") }}</span>
      <button
        type="button"
        class="shrink-0 cursor-pointer rounded-full bg-white px-4 py-1 font-medium ring-1 ring-amber-300 ring-inset hover:bg-amber-100"
        @click="leavePrivilegedMode"
      >
        {{ t("privileged_mode.leave") }}
      </button>
    </div>

    <div class="flex min-h-0 flex-1 flex-col md:flex-row">
      <details
        ref="mobilePane"
        class="mx-2 mb-2 shrink-0 md:hidden"
      >
        <summary class="flex cursor-pointer list-none items-center justify-between rounded-full px-4 py-2 text-sm font-semibold hover:bg-slate-900/5 [&::-webkit-details-marker]:hidden">
          {{ state.section ? t(`sections.${state.section}`) : t("pane_title") }}
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="size-4 text-slate-400"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              d="M6 9l6 6 6-6"
            />
          </svg>
        </summary>
        <div class="pt-1 pb-2">
          <FileTree />
          <PrivilegedModeSwitch />
        </div>
      </details>

      <aside
        id="side-pane"
        class="hidden w-64 shrink-0 overflow-y-auto px-3 pb-4 md:block"
      >
        <div class="px-4 pt-1 pb-3 text-lg font-medium">
          {{ t("pane_title") }}
        </div>
        <FileTree />
        <PrivilegedModeSwitch />
      </aside>

      <section class="mx-2 mb-2 flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-2xl bg-white md:mr-4 md:mb-4 md:ml-0">
        <RouterView />
      </section>
    </div>
    <NoticeBar />
    <UploadPanel />
    <VersionsPanel />
  </div>
</template>
