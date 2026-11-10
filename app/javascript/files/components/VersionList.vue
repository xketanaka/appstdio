<script setup lang="ts">
import { nextTick, ref, shallowRef } from "vue"
import { api, versionDownloadUrl, type Version } from "../api"
import { formatSize, formatTime } from "../format"
import { t } from "../i18n"
import { changed, notify, operationErrorMessages } from "../store"

// 履歴のパネルの「版」のタブ
const props = defineProps<{ fileId: number }>()

const versions = shallowRef<Version[]>([])
const canEdit = ref(false)
const editing = ref<number | null>(null)
const label = ref("")
const labelInput = ref<HTMLInputElement[]>([])

const load = async () => {
  try {
    const loaded = await api.versions(props.fileId)
    versions.value = loaded.versions
    canEdit.value = loaded.can_edit
  } catch (error) {
    notify(operationErrorMessages("versions", error).join(" "), { error: true })
  }
}

load()

const editLabel = async (version: Version) => {
  editing.value = version.id
  label.value = version.label ?? ""
  await nextTick()
  labelInput.value[0]?.focus()
}

const saveLabel = async (version: Version) => {
  try {
    await api.updateVersionLabel(props.fileId, version.id, label.value)
    editing.value = null
    await load()
  } catch (error) {
    notify(operationErrorMessages("versions", error).join(" "), { error: true })
  }
}

const restore = async (version: Version) => {
  try {
    const restored = await api.restoreVersion(props.fileId, version.id)
    notify(t("versions.restored", { from: version.number, version: restored.version }))
    await Promise.all([load(), changed()])
  } catch (error) {
    notify(operationErrorMessages("versions", error).join(" "), { error: true })
  }
}
</script>

<template>
  <ol>
    <li
      v-for="version in versions"
      :key="version.id"
      class="border-b border-slate-100 px-3 py-3 text-sm"
    >
      <div class="flex items-center gap-2">
        <span class="font-medium">{{ t("versions.number", { number: version.number }) }}</span>
        <span
          v-if="version.current"
          class="rounded-full bg-primary-100 px-2 py-0.5 text-xs text-primary-900"
        >{{ t("versions.current") }}</span>
        <span
          v-if="version.label && editing !== version.id"
          class="truncate text-slate-700"
        >{{ version.label }}</span>
      </div>
      <p class="mt-0.5 text-xs text-slate-500">
        {{ formatTime(version.created_at) }}・{{ version.creator ?? "-" }}・{{ formatSize(version.byte_size) }}
      </p>

      <form
        v-if="editing === version.id"
        class="mt-2 flex items-center gap-2"
        @submit.prevent="saveLabel(version)"
      >
        <label
          :for="`version-label-${version.id}`"
          class="sr-only"
        >{{ t("versions.label") }}</label>
        <input
          :id="`version-label-${version.id}`"
          ref="labelInput"
          v-model="label"
          type="text"
          class="input py-1"
          :placeholder="t('versions.label_placeholder')"
        >
        <button
          type="submit"
          class="btn btn-primary btn-sm"
        >
          {{ t("versions.save") }}
        </button>
        <button
          type="button"
          class="btn btn-secondary btn-sm"
          @click="editing = null"
        >
          {{ t("versions.cancel") }}
        </button>
      </form>

      <div
        v-else
        class="mt-2 flex flex-wrap items-center gap-2"
      >
        <span
          v-if="version.purged"
          class="text-xs text-slate-400"
        >{{ t("versions.purged") }}</span>
        <a
          v-else
          :href="versionDownloadUrl(fileId, version.id)"
          class="btn btn-secondary btn-sm"
        >{{ t("versions.download") }}</a>
        <button
          v-if="canEdit"
          type="button"
          class="btn btn-secondary btn-sm"
          @click="editLabel(version)"
        >
          {{ t(version.label ? "versions.change_label" : "versions.add_label") }}
        </button>
        <button
          v-if="canEdit && !version.current && !version.purged"
          type="button"
          class="btn btn-secondary btn-sm"
          @click="restore(version)"
        >
          {{ t("versions.restore") }}
        </button>
      </div>
    </li>
  </ol>
</template>
