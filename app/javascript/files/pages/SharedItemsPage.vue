<script setup lang="ts">
import { computed } from "vue"
import { api } from "../api"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import { chooseNewVersion, download, showVersions } from "../fileActions"
import { t } from "../i18n"
import { entryRow } from "../rows"
import { showSection } from "../store"
import { useLoad } from "../useLoad"

showSection("shared_with_me", t("sections.shared_with_me"))

const { data, status } = useLoad(api.sharedItems, () => null)

const rows = computed(() => data.value?.entries.map(entryRow) ?? [])
</script>

<template>
  <div class="shrink-0 px-6 pt-5 pb-3">
    <h1 class="truncate text-title">
      {{ t("sections.shared_with_me") }}
    </h1>
  </div>

  <FileList
    v-if="status === 'ready'"
    :rows="rows"
    :empty="t('shared_items.empty')"
    @download="download"
    @upload-version="chooseNewVersion"
    @versions="showVersions"
  />
  <LoadMessage
    v-else
    :status="status"
  />
</template>
