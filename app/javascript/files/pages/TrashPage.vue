<script setup lang="ts">
import { computed } from "vue"
import { api } from "../api"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import { t } from "../i18n"
import { trashRow } from "../rows"
import { showSection } from "../store"
import { useLoad } from "../useLoad"

showSection("trash", t("sections.trash"))

const { data, status } = useLoad(api.trash, () => null)

const rows = computed(() => data.value?.entries.map(trashRow) ?? [])
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
  />
  <LoadMessage
    v-else
    :status="status"
  />
</template>
