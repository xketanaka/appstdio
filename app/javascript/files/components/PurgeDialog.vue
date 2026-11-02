<script setup lang="ts">
import { computed, ref } from "vue"
import { t } from "../i18n"
import type { Row } from "../rows"
import { operationErrorMessages, purgeItems } from "../store"

// 取り消せないので、ゴミ箱から完全に削除する前に確かめる
const dialog = ref<HTMLDialogElement | null>(null)
const targets = ref<Row[]>([])
const errors = ref<string[]>([])
const submitting = ref(false)

const message = computed(() =>
  targets.value.length === 1
    ? t("purge.confirm_one", { name: targets.value[0].name })
    : t("purge.confirm_other", { count: targets.value.length }),
)

// 既定のフォーカスは、先に置いた「キャンセル」に当たる
const open = (rows: Row[]) => {
  targets.value = rows
  errors.value = []
  dialog.value?.showModal()
}

const close = () => dialog.value?.close()

const submit = async () => {
  if (submitting.value) return
  submitting.value = true
  try {
    await purgeItems(targets.value)
    close()
  } catch (error) {
    errors.value = operationErrorMessages("purge", error)
  } finally {
    submitting.value = false
  }
}

defineExpose({ open })
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="purge-title"
    aria-describedby="purge-message"
    class="m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl bg-white p-6 text-slate-800 shadow-xl backdrop:bg-slate-900/40"
  >
    <form @submit.prevent="submit">
      <h2
        id="purge-title"
        class="text-lg font-medium"
      >
        {{ t("purge.title") }}
      </h2>
      <p
        id="purge-message"
        class="mt-3 text-sm break-all text-slate-600"
      >
        {{ message }}
        <template v-if="targets.some((row) => row.kind === 'folder')">
          {{ t("purge.folder") }}
        </template>
      </p>

      <ul
        v-if="errors.length > 0"
        role="alert"
        class="mt-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"
      >
        <li
          v-for="error in errors"
          :key="error"
        >
          {{ error }}
        </li>
      </ul>

      <div class="mt-6 flex justify-end gap-2">
        <button
          type="button"
          class="btn btn-secondary"
          @click="close"
        >
          {{ t("purge.cancel") }}
        </button>
        <button
          type="submit"
          class="btn btn-danger"
          :disabled="submitting"
        >
          {{ t("purge.submit") }}
        </button>
      </div>
    </form>
  </dialog>
</template>
