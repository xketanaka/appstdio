<script setup lang="ts">
import { nextTick, ref, shallowRef, watch } from "vue"
import { api, versionDownloadUrl, type Version } from "../api"
import { formatSize, formatTime } from "../format"
import { t } from "../i18n"
import { changed, notify, operationErrorMessages, state } from "../store"

// 版の履歴。右から出るパネル（dialog）。行のメニューの「版の履歴」で state.versionsOf が入ると開く
const dialog = ref<HTMLDialogElement | null>(null)
const versions = shallowRef<Version[]>([])
const canEdit = ref(false)
const editing = ref<number | null>(null)
const label = ref("")
const labelInput = ref<HTMLInputElement[]>([])

const load = async () => {
  if (!state.versionsOf) return
  try {
    const loaded = await api.versions(state.versionsOf.id)
    versions.value = loaded.versions
    canEdit.value = loaded.can_edit
  } catch (error) {
    notify(operationErrorMessages("versions", error).join(" "), { error: true })
    close()
  }
}

watch(() => state.versionsOf, async (target) => {
  editing.value = null
  versions.value = []
  if (!target) return
  dialog.value?.showModal()
  await load()
})

const close = () => {
  dialog.value?.close()
  state.versionsOf = null
}

const editLabel = async (version: Version) => {
  editing.value = version.id
  label.value = version.label ?? ""
  await nextTick()
  labelInput.value[0]?.focus()
}

const saveLabel = async (version: Version) => {
  if (!state.versionsOf) return
  try {
    await api.updateVersionLabel(state.versionsOf.id, version.id, label.value)
    editing.value = null
    await load()
  } catch (error) {
    notify(operationErrorMessages("versions", error).join(" "), { error: true })
  }
}

const restore = async (version: Version) => {
  if (!state.versionsOf) return
  try {
    const restored = await api.restoreVersion(state.versionsOf.id, version.id)
    notify(t("versions.restored", { from: version.number, version: restored.version }))
    await Promise.all([load(), changed()])
  } catch (error) {
    notify(operationErrorMessages("versions", error).join(" "), { error: true })
  }
}
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="versions-title"
    class="m-0 ml-auto h-dvh max-h-dvh w-full max-w-md bg-white text-slate-800 shadow-xl backdrop:bg-slate-900/40"
    @close="state.versionsOf = null"
  >
    <div class="flex h-full flex-col">
      <header class="flex shrink-0 items-center justify-between gap-2 px-6 pt-5 pb-3">
        <h2
          id="versions-title"
          class="truncate text-lg font-medium"
        >
          {{ t("versions.title", { name: state.versionsOf?.name ?? "" }) }}
        </h2>
        <button
          type="button"
          class="cursor-pointer rounded-full p-1.5 text-slate-600 hover:bg-slate-900/5"
          :aria-label="t('versions.close')"
          @click="close"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="size-5"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              d="M6 6l12 12M18 6L6 18"
            />
          </svg>
        </button>
      </header>

      <ol class="min-h-0 flex-1 overflow-y-auto px-3 pb-4">
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
              :href="versionDownloadUrl(state.versionsOf?.id ?? 0, version.id)"
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
    </div>
  </dialog>
</template>
