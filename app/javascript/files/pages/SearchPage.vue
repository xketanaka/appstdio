<script setup lang="ts">
import { computed, ref } from "vue"
import { useRoute } from "vue-router"
import { api } from "../api"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import PurgeDialog from "../components/PurgeDialog.vue"
import { chooseNewVersion, download, showHistory, showSharing } from "../fileActions"
import { t } from "../i18n"
import { entryRow, trashRow, type Row } from "../rows"
import { notifyOperationError, restoreItems, setTitle, state } from "../store"
import { useLoad } from "../useLoad"

// 検索の結果。どこから探したか（in）は検索欄の範囲の印に残し、左ペインはどの区分も示さない
const route = useRoute()
const params = computed(() => ({
  q: String(route.query.q ?? ""),
  ...(route.query.in ? { in: String(route.query.in) } : {}),
  ...(route.query.all === "1" ? { all: "1" } : {}),
}))
const title = computed(() => t("search.title", { query: params.value.q }))

state.section = null
state.currentFolderId = null
setTitle(title.value)

const { data, status } = useLoad(() => api.search(params.value), params, (result) => {
  setTitle(title.value)
  state.searchOrigin = result.origin.in && result.origin.label ? { key: result.origin.in, label: result.origin.label } : null
})

const rows = computed<Row[]>(() => {
  if (!data.value) return []
  return data.value.trash
    ? data.value.entries.map((entry) => ({ ...trashRow(entry), location: { crumbs: entry.location, viaShared: entry.via_shared } }))
    : data.value.entries.map((entry) => ({ ...entryRow(entry), location: { crumbs: entry.location, viaShared: entry.via_shared } }))
})

const restore = async (items: Row[]) => {
  try {
    await restoreItems(items)
  } catch (error) {
    notifyOperationError("restore", error)
  }
}

const purgeDialog = ref<InstanceType<typeof PurgeDialog> | null>(null)
</script>

<template>
  <div class="shrink-0 px-6 pt-5 pb-3">
    <h1 class="truncate text-title">
      {{ title }}
    </h1>
    <p
      v-if="data?.truncated"
      role="status"
      class="mt-1 text-sm text-slate-600"
    >
      {{ t("search.truncated", { count: data.entries.length }) }}
    </p>
  </div>

  <FileList
    v-if="status === 'ready' && data?.trash"
    :rows="rows"
    :empty="t('search.empty')"
    trash
    can-edit
    located
    @restore="restore([$event])"
    @purge="purgeDialog?.open([$event])"
  />
  <FileList
    v-else-if="status === 'ready'"
    :rows="rows"
    :empty="t('search.empty')"
    located
    @download="download"
    @upload-version="chooseNewVersion"
    @history="showHistory"
    @share="showSharing"
  />
  <LoadMessage
    v-else
    :status="status"
  />
  <PurgeDialog ref="purgeDialog" />
</template>
