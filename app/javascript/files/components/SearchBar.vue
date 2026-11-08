<script setup lang="ts">
import { ref, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import { t } from "../i18n"
import { state } from "../store"

// 検索欄。開いている場所（state.searchOrigin）の中から探す。範囲の印から「すべての場所」に広げ、
// 元の場所へ戻せる。結果の画面では、URL の q・all を欄と印に映す
const route = useRoute()
const router = useRouter()
const query = ref("")
const everywhere = ref(false)
const menu = ref<HTMLDetailsElement | null>(null)

watch(() => route.fullPath, () => {
  const searching = route.name === "search"
  query.value = searching ? String(route.query.q ?? "") : ""
  everywhere.value = searching && route.query.all === "1"
}, { immediate: true })

const search = () => {
  const q = query.value.trim()
  if (!q) return
  const origin = state.searchOrigin?.key
  router.push({ name: "search", query: { q, ...(origin ? { in: origin } : {}), ...(everywhere.value ? { all: "1" } : {}) } })
}

const choose = (all: boolean) => {
  everywhere.value = all
  if (menu.value) menu.value.open = false
  if (route.name === "search") search()
}
</script>

<template>
  <form
    role="search"
    class="flex shrink-0 items-center gap-2 px-6 pt-4"
    @submit.prevent="search"
  >
    <details
      v-if="state.searchOrigin"
      ref="menu"
      class="relative shrink-0"
      data-dropdown
    >
      <summary
        class="flex max-w-48 cursor-pointer list-none items-center gap-1 rounded-full bg-primary-50 px-3 py-1.5 text-sm text-primary-900 hover:bg-primary-100 [&::-webkit-details-marker]:hidden"
        :title="t('search.scope')"
      >
        <span class="truncate">
          {{ everywhere ? t("search.everywhere") : t("search.within", { label: state.searchOrigin.label }) }}
        </span>
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          class="size-4 shrink-0"
          aria-hidden="true"
        >
          <path d="M6 9l6 6 6-6" />
        </svg>
      </summary>
      <div
        role="menu"
        class="absolute left-0 z-20 mt-1 w-56 rounded-xl bg-white py-1.5 text-sm shadow-lg ring-1 ring-slate-900/10"
      >
        <button
          v-for="all in [false, true]"
          :key="String(all)"
          type="button"
          role="menuitemradio"
          :aria-checked="everywhere === all"
          class="flex w-full cursor-pointer items-center gap-2 px-4 py-2 text-left hover:bg-slate-100"
          @click="choose(all)"
        >
          <span
            class="w-4 shrink-0 text-primary-700"
            aria-hidden="true"
          >{{ everywhere === all ? "✓" : "" }}</span>
          <span class="truncate">
            {{ all ? t("search.everywhere") : t("search.within", { label: state.searchOrigin.label }) }}
          </span>
        </button>
      </div>
    </details>
    <input
      v-model="query"
      type="search"
      autocomplete="off"
      class="input py-1.5"
      :aria-label="t('search.label')"
      :placeholder="t('search.placeholder')"
    >
  </form>
</template>
