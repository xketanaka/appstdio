<script setup lang="ts">
import { ref, shallowRef } from "vue"
import { api, type Activity } from "../api"
import { formatTime } from "../format"
import { t } from "../i18n"
import { notify, operationErrorMessages } from "../store"

// 履歴のパネルの「操作履歴」のタブ。フォルダなら配下の分も並ぶ
const props = defineProps<{ nodeId: number }>()

const activities = shallowRef<Activity[]>([])
const nextBefore = ref<number | null>(null)
const loading = ref(false)

const load = async (before?: number) => {
  loading.value = true
  try {
    const loaded = await api.activities(props.nodeId, before)
    activities.value = [...activities.value, ...loaded.activities]
    nextBefore.value = loaded.next_before
  } catch (error) {
    notify(operationErrorMessages("history", error).join(" "), { error: true })
  } finally {
    loading.value = false
  }
}

load()

// 閲覧できないフォルダの名前は null で届く
const folderName = (name: string | null) => name ?? t("history.hidden_folder")

const message = (activity: Activity) => {
  const name = activity.node.name
  switch (activity.action) {
    case "updated":
      return activity.detail.restored_from
        ? t("history.actions.restored_version", { name, from: activity.detail.restored_from, version: activity.detail.version })
        : t("history.actions.updated", { name, version: activity.detail.version })
    case "renamed":
      return t("history.actions.renamed", activity.detail)
    case "moved":
      return t("history.actions.moved", { name, from: folderName(activity.detail.from), to: folderName(activity.detail.to) })
    default:
      return t(`history.actions.${activity.action}`, { name })
  }
}
</script>

<template>
  <ol>
    <li
      v-for="activity in activities"
      :key="activity.id"
      class="border-b border-slate-100 px-3 py-3 text-sm"
    >
      <p class="break-all">
        {{ message(activity) }}
      </p>
      <p
        v-if="activity.location.length > 0"
        class="mt-0.5 truncate pl-2.5 text-xs text-slate-500"
      >
        {{ t("history.location", { path: activity.location.map(folderName).join(" / ") }) }}
      </p>
      <p class="mt-0.5 pl-2.5 text-xs text-slate-500">
        {{ activity.actor ?? t("history.system") }}・{{ formatTime(activity.created_at) }}
      </p>
    </li>
  </ol>
  <p
    v-if="!loading && activities.length === 0"
    class="py-10 text-center text-sm text-slate-500"
  >
    {{ t("history.empty") }}
  </p>
  <div
    v-if="nextBefore !== null"
    class="px-3 py-3"
  >
    <button
      type="button"
      class="btn btn-secondary btn-sm"
      :disabled="loading"
      @click="load(nextBefore ?? undefined)"
    >
      {{ t("history.more") }}
    </button>
  </div>
</template>
