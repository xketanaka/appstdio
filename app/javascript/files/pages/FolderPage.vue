<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { RouterLink, useRouter } from "vue-router"
import { api, type FolderSource } from "../api"
import FileIcon from "../components/FileIcon.vue"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import MoveDialog from "../components/MoveDialog.vue"
import NewFolderDialog from "../components/NewFolderDialog.vue"
import RenameDialog from "../components/RenameDialog.vue"
import SelectionToolbar from "../components/SelectionToolbar.vue"
import { t } from "../i18n"
import { entryRow, type Row } from "../rows"
import { endDrag, startDrag, useDropTargets } from "../dnd"
import { chooseNewVersion, download, showVersions } from "../fileActions"
import { changed, notifyOperationError, showFolder, trashItems } from "../store"
import { useLoad } from "../useLoad"
import { uploadFiles } from "../uploads"
import { useSelection } from "../useSelection"

const props = defineProps<{ source: FolderSource }>()

const { data, status } = useLoad(
  () => api.folder(props.source),
  () => props.source,
  showFolder,
)

const rows = computed(() => data.value?.entries.map(entryRow) ?? [])
const router = useRouter()
const { selected, select, clear } = useSelection(() => rows.value.map((row) => row.id))

watch(() => props.source, clear)

// プレビューはまだ無いので、ファイルを開く操作はダウンロードにする
const open = (row: Row) => {
  if (row.folderId !== null) router.push({ name: "folder", params: { id: row.folderId } })
  else if (row.kind === "file" && row.readable) download(row)
}

const selectedRows = () => rows.value.filter((row) => selected.has(row.id))

const trash = async (items: Row[]) => {
  try {
    await trashItems(items)
  } catch (error) {
    notifyOperationError("trash", error)
  }
}

// Esc で選択を解き、Delete（Mac は Backspace）で選んだものをゴミ箱へ入れる。
// ダイアログが開いているときと、文字を入力しているときは、その操作に任せる
const onKeydown = (event: KeyboardEvent) => {
  if (document.querySelector("dialog[open]") || (event.target as Element).closest("input, textarea")) return
  if (event.key === "Escape") clear()
  else if ((event.key === "Delete" || event.key === "Backspace") && selected.size > 0 && data.value?.can_edit) {
    event.preventDefault()
    trash(selectedRows())
  }
}
onMounted(() => document.addEventListener("keydown", onKeydown))
onBeforeUnmount(() => document.removeEventListener("keydown", onKeydown))

const renameDialog = ref<InstanceType<typeof RenameDialog> | null>(null)

// 選んでいない行をドラッグしたら、その行だけを選び直して動かす（Google ドライブと同じ）
const dragRows = (row: Row, event: DragEvent) => {
  if (!data.value) return
  if (!selected.has(row.id)) select(row.id, { toggle: false, range: false })
  startDrag(event, rows.value.filter((each) => selected.has(each.id)), data.value.folder.id)
}

// パンくずの祖先へも落とせる
const { over: overCrumb, handlers: crumbTarget } = useDropTargets()

const moveDialog = ref<InstanceType<typeof MoveDialog> | null>(null)
const moveSelected = () => moveDialog.value?.open(selectedRows())
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

const fileInput = ref<HTMLInputElement | null>(null)
const chooseFiles = () => {
  if (createMenu.value) createMenu.value.open = false
  fileInput.value?.click()
}
const uploadChosen = () => {
  if (!fileInput.value || !data.value) return
  uploadFiles([...(fileInput.value.files ?? [])], data.value.folder)
  // 同じファイルを続けて選んでも change が起きるよう、選んだものを空にする
  fileInput.value.value = ""
}

// パソコンのファイルを一覧へ落とせば、今のフォルダへアップロードする（フォルダの行に落とせばそのフォルダへ）
const { over: overFolder, handlers: folderTarget } = useDropTargets()

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
              class="-mx-1 rounded-full px-1 hover:underline"
              :class="{ 'bg-primary-100 text-primary-900 outline-2 outline-primary-600': overCrumb === crumb.id }"
              v-on="crumbTarget(crumb)"
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
          <button
            type="button"
            class="flex w-full cursor-pointer items-center gap-3 px-4 py-2 text-left hover:bg-slate-100"
            @click="chooseFiles"
          >
            <FileIcon :folder="false" />
            {{ t("folder.create_menu.upload") }}
          </button>
        </div>
      </details>
      <input
        ref="fileInput"
        type="file"
        multiple
        class="hidden"
        :aria-label="t('folder.create_menu.upload')"
        @change="uploadChosen"
      >
    </div>

    <div
      class="relative flex min-h-0 flex-1 flex-col"
      :class="{ 'm-1 rounded-xl bg-primary-50 outline-2 -outline-offset-2 outline-primary-600': overFolder === data.folder.id }"
      v-on="data.can_edit ? folderTarget(data.folder) : {}"
    >
      <FileList
      :rows="rows"
      :empty="t('folder.empty')"
      selectable
      :selected="selected"
      :can-edit="data.can_edit"
      :draggable="data.can_edit"
      @select="select"
      @open="open"
      @clear="clear"
      @move="moveRow"
      @rename="renameDialog?.open($event)"
      @trash="trash([$event])"
      @dragstart="dragRows"
      @dragend="endDrag"
      @download="download"
      @upload-version="chooseNewVersion"
      @versions="showVersions"
    >
      <template
        v-if="selected.size > 0"
        #toolbar
      >
        <SelectionToolbar
          :count="selected.size"
          @clear="clear"
        >
          <button
            v-if="data.can_edit"
            type="button"
            class="btn btn-secondary btn-sm"
            @click="moveSelected"
          >
            {{ t("selection.move") }}
          </button>
          <button
            v-if="data.can_edit"
            type="button"
            class="btn btn-danger btn-sm"
            @click="trash(selectedRows())"
          >
            {{ t("selection.trash") }}
          </button>
        </SelectionToolbar>
      </template>
    </FileList>
      <p
        v-if="overFolder === data.folder.id"
        class="pointer-events-none absolute inset-x-0 bottom-4 mx-auto w-fit rounded-full bg-primary-600 px-4 py-1.5 text-sm text-white shadow-lg"
      >
        {{ t("upload.drop_here", { destination: data.folder.label }) }}
      </p>
    </div>

    <NewFolderDialog
      ref="newFolderDialog"
      :parent-id="data.folder.id"
      @created="changed"
    />
    <RenameDialog ref="renameDialog" />
    <MoveDialog
      ref="moveDialog"
      :from="data.folder"
    />
  </template>
  <LoadMessage
    v-else
    :status="status"
  />
</template>
