<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { RouterLink, useRouter } from "vue-router"
import { api, type FolderSource } from "../api"
import FileIcon from "../components/FileIcon.vue"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import MoveDialog from "../components/MoveDialog.vue"
import NewFolderDialog from "../components/NewFolderDialog.vue"
import { t } from "../i18n"
import { entryRow, type Row } from "../rows"
import { reloadTree, showFolder } from "../store"
import { useLoad } from "../useLoad"
import { useSelection } from "../useSelection"

const props = defineProps<{ source: FolderSource }>()

const { data, status, reload } = useLoad(
  () => api.folder(props.source),
  () => props.source,
  showFolder,
)

const rows = computed(() => data.value?.entries.map(entryRow) ?? [])
const router = useRouter()
const { selected, select, clear } = useSelection(() => rows.value.map((row) => row.id))

watch(() => props.source, clear)

const open = (row: Row) => {
  if (row.folderId !== null) router.push({ name: "folder", params: { id: row.folderId } })
}

// ダイアログが開いているときの Esc はダイアログを閉じるだけにする
const clearOnEscape = (event: KeyboardEvent) => {
  if (event.key === "Escape" && !document.querySelector("dialog[open]")) clear()
}
onMounted(() => document.addEventListener("keydown", clearOnEscape))
onBeforeUnmount(() => document.removeEventListener("keydown", clearOnEscape))

const moveDialog = ref<InstanceType<typeof MoveDialog> | null>(null)
const moveSelected = () => moveDialog.value?.open(rows.value.filter((row) => selected.has(row.id)))
const moveRow = (row: Row) => {
  select(row.id, { toggle: false, range: false })
  moveDialog.value?.open([row])
}

const createMenu = ref<HTMLDetailsElement | null>(null)
const newFolderDialog = ref<InstanceType<typeof NewFolderDialog> | null>(null)

const openNewFolder = () => {
  if (createMenu.value) createMenu.value.open = false
  newFolderDialog.value?.open()
}

// 左ペインのツリーにはドライブ直下のフォルダが出るので、そちらも読み直す
const changed = () => Promise.all([reload(), reloadTree()])
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
      selectable
      :selected="selected"
      :can-move="data.can_edit"
      @select="select"
      @open="open"
      @clear="clear"
      @move="moveRow"
    >
      <template
        v-if="selected.size > 0"
        #toolbar
      >
        <div
          role="toolbar"
          :aria-label="t('selection.count', { count: selected.size })"
          class="flex items-center gap-2 text-sm text-slate-800"
        >
          <button
            type="button"
            class="cursor-pointer rounded-full p-1.5 text-slate-600 hover:bg-slate-900/5"
            :aria-label="t('selection.clear')"
            @click="clear"
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
          <span class="mr-2">{{ t("selection.count", { count: selected.size }) }}</span>
          <button
            v-if="data.can_edit"
            type="button"
            class="btn btn-secondary btn-sm"
            @click="moveSelected"
          >
            {{ t("selection.move") }}
          </button>
        </div>
      </template>
    </FileList>

    <NewFolderDialog
      ref="newFolderDialog"
      :parent-id="data.folder.id"
      @created="changed"
    />
    <MoveDialog
      ref="moveDialog"
      :from="data.folder"
      @moved="changed"
    />
  </template>
  <LoadMessage
    v-else
    :status="status"
  />
</template>
