<script setup lang="ts">
import { computed } from "vue"
import { RouterLink } from "vue-router"
import type { SectionKey, TreeFolder } from "../api"
import { t } from "../i18n"
import { state } from "../store"
import TreeFolderItem from "./TreeFolderItem.vue"
import { useDropTargets } from "../dnd"

// rootId は、そのドライブのルート（落とし先にできる）。マイドライブは初めて開くまで無い
type Section = { key: SectionKey, to: { name: string }, folders?: TreeFolder[], rootId?: number }

const sections = computed<Section[]>(() => [
  {
    key: "shared_drive", to: { name: "shared_drive" },
    folders: state.tree?.shared_drive?.folders ?? [], rootId: state.tree?.shared_drive?.id,
  },
  { key: "shared_with_me", to: { name: "shared_with_me" } },
  {
    key: "my_drive", to: { name: "my_drive" },
    folders: state.tree?.my_drive?.folders ?? [], rootId: state.tree?.my_drive?.id,
  },
  { key: "trash", to: { name: "trash" } },
])

const { over, handlers } = useDropTargets()
const dropTarget = (section: Section) =>
  section.rootId === undefined ? {} : handlers({ id: section.rootId, label: t(`sections.${section.key}`) })

// フォルダを開いているときは、区分ではなくそのフォルダを選択中として示す
const current = (key: SectionKey) => key === state.section && state.currentFolderId === null

const toggle = (key: SectionKey, event: Event) => {
  if ((event.target as HTMLDetailsElement).open) state.openSections.add(key)
  else state.openSections.delete(key)
}
</script>

<template>
  <nav :aria-label="t('tree.label')">
    <template
      v-for="section in sections"
      :key="section.key"
    >
      <details
        v-if="section.folders"
        class="group"
        :open="state.openSections.has(section.key)"
        @toggle="toggle(section.key, $event)"
      >
        <summary
          class="nav-item cursor-pointer list-none pl-2.5 [&::-webkit-details-marker]:hidden"
          :class="{ 'nav-item-current': current(section.key), 'bg-primary-50 outline-2 -outline-offset-2 outline-primary-600': over !== null && over === section.rootId }"
          v-on="dropTarget(section)"
        >
          <svg
            viewBox="0 0 24 24"
            fill="currentColor"
            aria-hidden="true"
            class="size-3 shrink-0 text-slate-400 transition-transform group-open:rotate-90"
          >
            <path d="M8 4l10 8-10 8V4Z" />
          </svg>
          <RouterLink
            :to="section.to"
            :aria-current="current(section.key) ? 'page' : undefined"
            class="truncate"
          >
            {{ t(`sections.${section.key}`) }}
          </RouterLink>
        </summary>

        <TreeFolderItem
          v-for="folder in section.folders"
          :key="folder.id"
          :folder="folder"
          :depth="0"
        />
      </details>
      <div
        v-else
        class="nav-item pl-7.5"
        :class="{ 'nav-item-current': current(section.key) }"
      >
        <RouterLink
          :to="section.to"
          :aria-current="current(section.key) ? 'page' : undefined"
          class="truncate"
        >
          {{ t(`sections.${section.key}`) }}
        </RouterLink>
      </div>
    </template>
  </nav>
</template>
