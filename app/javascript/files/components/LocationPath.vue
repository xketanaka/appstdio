<script setup lang="ts">
import { RouterLink } from "vue-router"
import type { FolderLink } from "../api"
import { t } from "../i18n"

// 検索の結果の、根元からの場所。途中から始まるときは「共有されたアイテム」から並べる
const props = defineProps<{ crumbs: FolderLink[], viaShared: boolean }>()

const full = [...(props.viaShared ? [t("sections.shared_with_me")] : []), ...props.crumbs.map((crumb) => crumb.label)].join(" / ")
</script>

<template>
  <span
    class="block truncate"
    :title="full"
  >
    <template v-if="viaShared">
      <RouterLink
        :to="{ name: 'shared_with_me' }"
        class="hover:underline"
      >{{ t("sections.shared_with_me") }}</RouterLink>
      <span
        v-if="crumbs.length > 0"
        aria-hidden="true"
      > / </span>
    </template>
    <template
      v-for="(crumb, index) in crumbs"
      :key="crumb.id"
    >
      <RouterLink
        :to="{ name: 'folder', params: { id: crumb.id } }"
        class="hover:underline"
      >{{ crumb.label }}</RouterLink>
      <span
        v-if="index < crumbs.length - 1"
        aria-hidden="true"
      > / </span>
    </template>
  </span>
</template>
