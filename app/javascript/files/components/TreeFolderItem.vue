<script setup lang="ts">
import { computed } from "vue"
import { RouterLink } from "vue-router"
import type { TreeFolder } from "../api"
import { t } from "../i18n"
import { state, toggleFolder } from "../store"
import FileIcon from "./FileIcon.vue"

// ツリーのフォルダの1行と、開いていればその下の階層。子は開いたときに読み込む
const props = defineProps<{ folder: TreeFolder, depth: number }>()

const open = computed(() => state.openFolders.has(props.folder.id))
const current = computed(() => state.currentFolderId === props.folder.id)
const children = computed(() => state.children.get(props.folder.id) ?? [])
</script>

<template>
  <div
    class="nav-item gap-1 pr-3 pl-1"
    :class="{ 'nav-item-current': current }"
    :style="{ marginLeft: `${(depth + 1) * 1}rem` }"
  >
    <button
      v-if="folder.has_children"
      type="button"
      class="flex size-5 shrink-0 cursor-pointer items-center justify-center rounded-full text-slate-400 hover:bg-slate-900/5"
      :aria-label="t(open ? 'tree.collapse' : 'tree.expand', { name: folder.name })"
      :aria-expanded="open"
      @click="toggleFolder(folder.id)"
    >
      <svg
        viewBox="0 0 24 24"
        fill="currentColor"
        aria-hidden="true"
        class="size-3 transition-transform"
        :class="{ 'rotate-90': open }"
      >
        <path d="M8 4l10 8-10 8V4Z" />
      </svg>
    </button>
    <span
      v-else
      class="size-5 shrink-0"
    />
    <FileIcon folder />
    <RouterLink
      v-if="folder.readable"
      :to="{ name: 'folder', params: { id: folder.id } }"
      :aria-current="current ? 'page' : undefined"
      class="truncate"
    >
      {{ folder.name }}
    </RouterLink>
    <span
      v-else
      class="truncate text-slate-400"
    >{{ folder.name }}</span>
  </div>
  <template v-if="open">
    <TreeFolderItem
      v-for="child in children"
      :key="child.id"
      :folder="child"
      :depth="depth + 1"
    />
  </template>
</template>
