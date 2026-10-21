<script setup lang="ts">
import { computed } from "vue"
import { RouterLink } from "vue-router"
import { api, type FolderSource } from "../api"
import FileList from "../components/FileList.vue"
import LoadMessage from "../components/LoadMessage.vue"
import { t } from "../i18n"
import { entryRow } from "../rows"
import { showSection } from "../store"
import { buttonClass } from "../ui"
import { useLoad } from "../useLoad"

const props = defineProps<{ source: FolderSource }>()

const { data, status } = useLoad(
  () => api.folder(props.source),
  () => props.source,
  (payload) => showSection(payload.section, payload.folder.label),
)

const rows = computed(() => data.value?.entries.map(entryRow) ?? [])
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
      <button
        v-if="data.can_edit"
        type="button"
        :class="buttonClass('primary', 'sm')"
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
            d="M12 5v14M5 12h14"
          />
        </svg>
        {{ t("folder.create") }}
      </button>
    </div>

    <FileList
      :rows="rows"
      :empty="t('folder.empty')"
    />
  </template>
  <LoadMessage
    v-else
    :status="status"
  />
</template>
