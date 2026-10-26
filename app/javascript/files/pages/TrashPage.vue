<script setup lang="ts">
import { computed } from "vue"
import { api } from "../api"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import SelectionToolbar from "../components/SelectionToolbar.vue"
import { t } from "../i18n"
import { trashRow, type Row } from "../rows"
import { notifyOperationError, restoreItems, showSection } from "../store"
import { useLoad } from "../useLoad"
import { useSelection } from "../useSelection"

showSection("trash", t("sections.trash"))

const { data, status } = useLoad(api.trash, () => null)

const rows = computed(() => data.value?.entries.map(trashRow) ?? [])
const { selected, select, clear } = useSelection(() => rows.value.map((row) => row.id))

// ゴミ箱に出ているのは、元の親フォルダを編集できるものだけなので、どれも元に戻す操作ができる
const restore = async (items: Row[]) => {
  try {
    await restoreItems(items)
  } catch (error) {
    notifyOperationError("restore", error)
  }
}
</script>

<template>
  <div class="shrink-0 px-6 pt-5 pb-3">
    <h1 class="truncate text-title">
      {{ t("sections.trash") }}
    </h1>
  </div>

  <FileList
    v-if="status === 'ready'"
    :rows="rows"
    :empty="t('trash.empty')"
    trash
    selectable
    can-edit
    :selected="selected"
    @select="select"
    @clear="clear"
    @restore="restore([$event])"
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
          type="button"
          class="btn btn-secondary btn-sm"
          @click="restore(rows.filter((row) => selected.has(row.id)))"
        >
          {{ t("selection.restore") }}
        </button>
      </SelectionToolbar>
    </template>
  </FileList>
  <LoadMessage
    v-else
    :status="status"
  />
</template>
