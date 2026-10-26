<script setup lang="ts">
import { nextTick, ref } from "vue"
import { api } from "../api"
import { t } from "../i18n"
import type { Row } from "../rows"
import { changed, operationErrorMessages } from "../store"

const dialog = ref<HTMLDialogElement | null>(null)
const input = ref<HTMLInputElement | null>(null)
const target = ref<Row | null>(null)
const name = ref("")
const errors = ref<string[]>([])
const submitting = ref(false)

// 入力欄には拡張子まで含めた名前全体を入れる。最初に選んでおくのは拡張子を除いた部分だけで、
// そのまま打てば拡張子は残る。拡張子も変えたいときは、そのまま選び直して編集できる
const selectBaseName = () => {
  const dot = name.value.lastIndexOf(".")
  const end = target.value?.kind === "file" && dot > 0 ? dot : name.value.length
  input.value?.setSelectionRange(0, end)
}

const open = async (row: Row) => {
  target.value = row
  name.value = row.name
  errors.value = []
  dialog.value?.showModal()
  await nextTick()
  input.value?.focus()
  selectBaseName()
}

const close = () => dialog.value?.close()

const submit = async () => {
  if (submitting.value || target.value === null) return
  submitting.value = true
  try {
    await api.rename(target.value.id, name.value)
    close()
    await changed()
  } catch (error) {
    errors.value = operationErrorMessages("rename", error)
    input.value?.focus()
  } finally {
    submitting.value = false
  }
}

defineExpose({ open })
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="rename-title"
    class="m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl bg-white p-6 text-slate-800 shadow-xl backdrop:bg-slate-900/40"
  >
    <form @submit.prevent="submit">
      <h2
        id="rename-title"
        class="text-lg font-medium"
      >
        {{ t("rename.title") }}
      </h2>

      <label
        for="rename-name"
        class="sr-only"
      >{{ t("rename.name") }}</label>
      <input
        id="rename-name"
        ref="input"
        v-model="name"
        type="text"
        autocomplete="off"
        class="input mt-4"
        :aria-invalid="errors.length > 0"
        :aria-describedby="errors.length > 0 ? 'rename-errors' : undefined"
      >

      <ul
        v-if="errors.length > 0"
        id="rename-errors"
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

      <div class="mt-6 flex justify-end gap-2">
        <button
          type="button"
          class="btn btn-secondary"
          @click="close"
        >
          {{ t("rename.cancel") }}
        </button>
        <button
          type="submit"
          class="btn btn-primary"
          :disabled="submitting"
        >
          {{ t("rename.submit") }}
        </button>
      </div>
    </form>
  </dialog>
</template>
