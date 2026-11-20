<script setup lang="ts">
import { ref, shallowRef, watch } from "vue"
import { api, type GroupDriveSetting } from "../api"
import { t } from "../i18n"
import { changed, notify, state } from "../store"

// 部署のグループドライブを使うかの設定。左ペインの「グループドライブ」の「⋮」で state.groupDriveSettingsOpen が
// 立つと開く。並ぶのは自分が管理できるグループ（グループ管理と同じ範囲）。
// 使わないにするときは、その行で中身をゴミ箱へ移すかを選んでもらう（既定は置かない）
const dialog = ref<HTMLDialogElement | null>(null)
const groups = shallowRef<GroupDriveSetting[] | null>(null)
const confirming = ref<number | null>(null)
const errors = ref<string[]>([])
const busy = ref(false)

const load = async () => {
  try {
    groups.value = (await api.groupDrives()).groups
  } catch (error) {
    errors.value = [t("group_drives.load_failed")]
    console.error(error)
  }
}

watch(() => state.groupDriveSettingsOpen, (open) => {
  if (!open) return
  groups.value = null
  confirming.value = null
  errors.value = []
  dialog.value?.showModal()
  load()
})

const close = () => dialog.value?.close()

const run = async (action: () => Promise<void>, message: string) => {
  if (busy.value) return
  busy.value = true
  errors.value = []
  try {
    await action()
    confirming.value = null
    notify(message)
    await Promise.all([load(), changed()])
  } catch (error) {
    errors.value = [t("group_drives.failed")]
    console.error(error)
  } finally {
    busy.value = false
  }
}

const enable = (group: GroupDriveSetting) =>
  run(() => api.enableGroupDrive(group.id), t("group_drives.enabled_done", { name: group.name }))

const disable = (group: GroupDriveSetting, trash: boolean) =>
  run(() => api.disableGroupDrive(group.id, trash), t("group_drives.disabled_done", { name: group.name }))
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="group-drives-title"
    class="m-auto w-[calc(100%-2rem)] max-w-lg rounded-2xl bg-white p-6 text-slate-800 shadow-xl backdrop:bg-slate-900/40"
    @close="state.groupDriveSettingsOpen = false"
  >
    <h2
      id="group-drives-title"
      class="text-lg font-medium"
    >
      {{ t("group_drives.title") }}
    </h2>
    <p class="mt-2 text-sm text-slate-600">
      {{ t("group_drives.description") }}
    </p>

    <ul
      class="mt-4 max-h-80 overflow-y-auto rounded-xl border border-slate-200"
      :aria-label="t('group_drives.title')"
    >
      <li
        v-if="groups === null"
        class="px-4 py-8 text-center text-sm text-slate-500"
      >
        {{ t("group_drives.loading") }}
      </li>
      <li
        v-else-if="groups.length === 0"
        class="px-4 py-8 text-center text-sm text-slate-500"
      >
        {{ t("group_drives.empty") }}
      </li>
      <li
        v-for="group in groups ?? []"
        :key="group.id"
        class="border-b border-slate-100 px-4 py-2.5 text-sm last:border-b-0"
      >
        <div class="flex items-center gap-3">
          <span
            class="min-w-0 flex-1 truncate"
            :title="group.path.join(' / ')"
          >{{ group.name }}</span>
          <span
            v-if="group.enabled"
            class="shrink-0 rounded-full bg-primary-50 px-2 py-0.5 text-xs font-medium text-primary-700"
          >{{ t("group_drives.in_use") }}</span>
          <button
            v-if="!group.enabled"
            type="button"
            class="btn btn-secondary btn-sm"
            :disabled="busy"
            :aria-label="t('group_drives.enable_label', { name: group.name })"
            @click="enable(group)"
          >
            {{ t("group_drives.enable") }}
          </button>
          <button
            v-else-if="confirming !== group.id"
            type="button"
            class="btn btn-secondary btn-sm"
            :disabled="busy"
            :aria-label="t('group_drives.disable_label', { name: group.name })"
            @click="confirming = group.id"
          >
            {{ t("group_drives.disable") }}
          </button>
        </div>
        <div
          v-if="confirming === group.id"
          role="group"
          :aria-label="t('group_drives.disable_label', { name: group.name })"
          class="mt-2 rounded-xl bg-canvas px-4 py-3"
        >
          <p>{{ t("group_drives.confirm") }}</p>
          <ul class="mt-1 list-disc pl-5 text-xs text-slate-600">
            <li>{{ t("group_drives.trash_note") }}</li>
            <li>{{ t("group_drives.keep_note") }}</li>
          </ul>
          <div class="mt-3 flex flex-wrap justify-end gap-2">
            <button
              type="button"
              class="btn btn-secondary btn-sm"
              @click="confirming = null"
            >
              {{ t("group_drives.cancel") }}
            </button>
            <button
              type="button"
              class="btn btn-secondary btn-sm"
              :disabled="busy"
              @click="disable(group, false)"
            >
              {{ t("group_drives.keep") }}
            </button>
            <button
              type="button"
              class="btn btn-danger btn-sm"
              :disabled="busy"
              @click="disable(group, true)"
            >
              {{ t("group_drives.trash") }}
            </button>
          </div>
        </div>
      </li>
    </ul>

    <ul
      v-if="errors.length > 0"
      role="alert"
      class="mt-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"
    >
      <li
        v-for="message in errors"
        :key="message"
      >
        {{ message }}
      </li>
    </ul>

    <div class="mt-6 flex justify-end">
      <button
        type="button"
        class="btn btn-secondary"
        @click="close"
      >
        {{ t("group_drives.close") }}
      </button>
    </div>
  </dialog>
</template>
