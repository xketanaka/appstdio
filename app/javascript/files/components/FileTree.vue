<script setup lang="ts">
import { computed } from "vue"
import { RouterLink } from "vue-router"
import type { SectionKey, TreeFolder } from "../api"
import { t } from "../i18n"
import { state } from "../store"
import TreeFolderItem from "./TreeFolderItem.vue"
import { useDropTargets } from "../dnd"

// rootId は、そのドライブのルート（落とし先にできる）。マイドライブは初めて開くまで無い。
// drives は、グループドライブ・プロジェクトドライブの区分に並べるドライブのルート。区分そのものは開く画面を持たない。
// manageable なら、区分の「⋮」から使うグループを設定できる（ドライブが1つも無くても区分を出す）
type Section
  = | { key: SectionKey, to: { name: string }, folders?: TreeFolder[], rootId?: number }
    | { key: SectionKey, drives: TreeFolder[], manageable: boolean }

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
  ...(["group_drives", "project_drives"] as const)
    .map((key) => ({
      key, drives: state.tree?.[key] ?? [],
      manageable: key === "group_drives" && (state.tree?.can_manage_group_drives ?? false),
    }))
    .filter((section) => section.drives.length > 0 || section.manageable),
  { key: "trash", to: { name: "trash" } },
])

const { over, handlers } = useDropTargets()
const dropTarget = (section: Section) =>
  !("rootId" in section) || section.rootId === undefined
    ? {}
    : handlers({ id: section.rootId, label: t(`sections.${section.key}`) })

// フォルダを開いているときは、区分ではなくそのフォルダを選択中として示す
const current = (key: SectionKey) => key === state.section && state.currentFolderId === null

const toggle = (key: SectionKey, event: Event) => {
  if ((event.target as HTMLDetailsElement).open) state.openSections.add(key)
  else state.openSections.delete(key)
}

const openGroupDriveSettings = (event: Event) => {
  (event.currentTarget as HTMLElement).closest("details")?.removeAttribute("open")
  state.groupDriveSettingsOpen = true
}
</script>

<template>
  <nav :aria-label="t('tree.label')">
    <template
      v-for="section in sections"
      :key="section.key"
    >
      <div
        v-if="'drives' in section"
        class="relative"
      >
        <details
          class="group"
          :open="state.openSections.has(section.key)"
          @toggle="toggle(section.key, $event)"
        >
          <summary
            class="nav-item cursor-pointer list-none pl-2.5 [&::-webkit-details-marker]:hidden"
            :class="{ 'pr-10': section.manageable }"
          >
            <svg
              viewBox="0 0 24 24"
              fill="currentColor"
              aria-hidden="true"
              class="size-3 shrink-0 text-slate-400 transition-transform group-open:rotate-90"
            >
              <path d="M8 4l10 8-10 8V4Z" />
            </svg>
            <span class="truncate">{{ t(`sections.${section.key}`) }}</span>
          </summary>

          <TreeFolderItem
            v-for="drive in section.drives"
            :key="drive.id"
            :folder="drive"
            :depth="0"
          />
          <p
            v-if="section.drives.length === 0"
            class="py-1 pl-7.5 text-xs text-slate-500"
          >
            {{ t("group_drives.none") }}
          </p>
        </details>
        <!-- 区分の行の上に重ねる。summary の中に置くと、押したときに区分も開閉する。
             data-dropdown を外すと外側クリックと Esc で閉じなくなる（application.ts が拾っている） -->
        <details
          v-if="section.manageable"
          class="absolute top-0.5 right-1"
          data-dropdown
        >
          <summary
            class="flex size-8 cursor-pointer list-none items-center justify-center rounded-full text-slate-500 hover:bg-slate-900/5 [&::-webkit-details-marker]:hidden"
            :aria-label="t('group_drives.menu')"
            :title="t('group_drives.menu')"
          >
            <svg
              viewBox="0 0 24 24"
              fill="currentColor"
              class="size-4"
              aria-hidden="true"
            >
              <circle
                cx="12"
                cy="5"
                r="1.75"
              />
              <circle
                cx="12"
                cy="12"
                r="1.75"
              />
              <circle
                cx="12"
                cy="19"
                r="1.75"
              />
            </svg>
          </summary>
          <div class="absolute right-0 z-10 mt-1 w-56 rounded-xl bg-white py-1.5 text-sm shadow-lg ring-1 ring-slate-900/10">
            <button
              type="button"
              class="block w-full cursor-pointer px-4 py-2 text-left hover:bg-slate-100"
              @click="openGroupDriveSettings"
            >
              {{ t("group_drives.open_settings") }}
            </button>
          </div>
        </details>
      </div>
      <details
        v-else-if="section.folders"
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
