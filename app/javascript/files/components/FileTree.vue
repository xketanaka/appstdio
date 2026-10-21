<script setup lang="ts">
import { computed } from "vue"
import { RouterLink } from "vue-router"
import type { SectionKey, TreeFolder } from "../api"
import { t } from "../i18n"
import { state } from "../store"
import FileIcon from "./FileIcon.vue"

type Section = { key: SectionKey, to: { name: string }, folders?: TreeFolder[] }

const sections = computed<Section[]>(() => [
  { key: "shared_drive", to: { name: "shared_drive" }, folders: state.tree?.shared_drive ?? [] },
  { key: "shared_with_me", to: { name: "shared_with_me" } },
  { key: "my_drive", to: { name: "my_drive" }, folders: state.tree?.my_drive ?? [] },
  { key: "trash", to: { name: "trash" } },
])

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
          :class="{ 'nav-item-current': section.key === state.section }"
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
            :aria-current="section.key === state.section ? 'page' : undefined"
            class="truncate"
          >
            {{ t(`sections.${section.key}`) }}
          </RouterLink>
        </summary>

        <div
          v-for="folder in section.folders"
          :key="folder.id"
          class="nav-item ml-5"
        >
          <FileIcon folder />
          <RouterLink
            v-if="folder.readable"
            :to="{ name: 'folder', params: { id: folder.id } }"
            class="truncate"
          >
            {{ folder.name }}
          </RouterLink>
          <span
            v-else
            class="truncate text-slate-400"
          >{{ folder.name }}</span>
        </div>
      </details>
      <div
        v-else
        class="nav-item pl-7.5"
        :class="{ 'nav-item-current': section.key === state.section }"
      >
        <RouterLink
          :to="section.to"
          :aria-current="section.key === state.section ? 'page' : undefined"
          class="truncate"
        >
          {{ t(`sections.${section.key}`) }}
        </RouterLink>
      </div>
    </template>
  </nav>
</template>
