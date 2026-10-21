<script setup lang="ts">
import { computed, ref } from "vue"
import { RouterLink } from "vue-router"
import { api, type FolderSource } from "../api"
import FileIcon from "../components/FileIcon.vue"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import NewFolderDialog from "../components/NewFolderDialog.vue"
import { t } from "../i18n"
import { entryRow } from "../rows"
import { reloadTree, showSection } from "../store"
import { useLoad } from "../useLoad"

const props = defineProps<{ source: FolderSource }>()

const { data, status, reload } = useLoad(
  () => api.folder(props.source),
  () => props.source,
  (payload) => showSection(payload.section, payload.folder.label),
)

const rows = computed(() => data.value?.entries.map(entryRow) ?? [])

const createMenu = ref<HTMLDetailsElement | null>(null)
const newFolderDialog = ref<InstanceType<typeof NewFolderDialog> | null>(null)

const openNewFolder = () => {
  if (createMenu.value) createMenu.value.open = false
  newFolderDialog.value?.open()
}

// 左ペインのツリーにはドライブ直下のフォルダが出るので、そちらも読み直す
const created = () => Promise.all([reload(), reloadTree()])
</script>

<template>
  <template v-if="data && status === 'ready'">
    <div class="flex shrink-0 items-center justify-between gap-4 px-6 pt-5 pb-3">
      <div class="min-w-0">
        <nav
          v-if="data.breadcrumbs.length > 0 || data.via_shared"
          :aria-label="t('folder.breadcrumbs')"
          class="mb-0.5 truncate text-sm text-slate-500"
        >
          <template v-if="data.via_shared">
            <RouterLink
              :to="{ name: 'shared_with_me' }"
              class="hover:underline"
            >
              {{ t("sections.shared_with_me") }}
            </RouterLink>
            <span aria-hidden="true"> / </span>
          </template>
          <template
            v-for="crumb in data.breadcrumbs"
            :key="crumb.id"
          >
            <RouterLink
              :to="{ name: 'folder', params: { id: crumb.id } }"
              class="hover:underline"
            >
              {{ crumb.label }}
            </RouterLink>
            <span aria-hidden="true"> / </span>
          </template>
        </nav>
        <h1 class="truncate text-title">
          {{ data.folder.label }}
        </h1>
      </div>
      <!-- data-dropdown を外すと外側クリックと Esc で閉じなくなる（application.ts が拾っている） -->
      <details
        v-if="data.can_edit"
        ref="createMenu"
        class="relative shrink-0"
        data-dropdown
      >
        <summary class="btn btn-primary btn-sm list-none [&::-webkit-details-marker]:hidden">
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
            d="M12 5v14M5 12h14"
            />
          </svg>
          {{ t("folder.create") }}
        </summary>
        <div class="absolute right-0 z-10 mt-1 w-56 rounded-xl bg-white py-1.5 text-sm shadow-lg ring-1 ring-slate-900/10">
          <button
            type="button"
            class="flex w-full cursor-pointer items-center gap-3 px-4 py-2 text-left hover:bg-slate-100"
            @click="openNewFolder"
          >
            <FileIcon folder />
            {{ t("folder.create_menu.folder") }}
          </button>
          <span
            class="flex items-center gap-3 px-4 py-2 text-slate-400"
            aria-disabled="true"
          >
            <FileIcon :folder="false" />
            {{ t("folder.create_menu.upload") }}
          </span>
        </div>
      </details>
    </div>

    <FileList
      :rows="rows"
      :empty="t('folder.empty')"
    />

    <NewFolderDialog
      ref="newFolderDialog"
      :parent-id="data.folder.id"
      @created="created"
    />
  </template>
  <LoadMessage
    v-else
    :status="status"
  />
</template>
