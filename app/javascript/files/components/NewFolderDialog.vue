<script setup lang="ts">
import { nextTick, ref } from "vue"
import { api, ForbiddenError, NotFoundError, ValidationError } from "../api"
import { t } from "../i18n"

const props = defineProps<{ parentId: number }>()
const emit = defineEmits<{ created: [folder: { id: number, name: string }] }>()

const dialog = ref<HTMLDialogElement | null>(null)
const input = ref<HTMLInputElement | null>(null)
const name = ref("")
const errors = ref<string[]>([])
const submitting = ref(false)

// 名前を入れた状態で開き、全体を選んでおく。そのまま打てば置き換わる
const open = async () => {
  name.value = t("new_folder.default_name")
  errors.value = []
  dialog.value?.showModal()
  await nextTick()
  input.value?.select()
}

const close = () => dialog.value?.close()

const submit = async () => {
  if (submitting.value) return
  submitting.value = true
  try {
    const folder = await api.createFolder(props.parentId, name.value)
    close()
    emit("created", folder)
  } catch (error) {
    if (error instanceof ValidationError) errors.value = error.messages
    else if (error instanceof NotFoundError) errors.value = [t("new_folder.not_found")]
    else if (error instanceof ForbiddenError) errors.value = [t("new_folder.forbidden")]
    else {
      // 時間をおいて直りうるのは、サーバの誤りや通信の失敗だけ
      errors.value = [t("new_folder.failed")]
      console.error(error)
    }
    input.value?.select()
  } finally {
    submitting.value = false
  }
}

defineExpose({ open })
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="new-folder-title"
    class="m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl bg-white p-6 text-slate-800 shadow-xl backdrop:bg-slate-900/40"
  >
    <form @submit.prevent="submit">
      <h2
        id="new-folder-title"
        class="text-lg font-medium"
      >
        {{ t("new_folder.title") }}
      </h2>

      <label
        for="new-folder-name"
        class="sr-only"
      >{{ t("new_folder.name") }}</label>
      <input
        id="new-folder-name"
        ref="input"
        v-model="name"
        type="text"
        autocomplete="off"
        class="input mt-4"
        :aria-invalid="errors.length > 0"
        :aria-describedby="errors.length > 0 ? 'new-folder-errors' : undefined"
      >

      <ul
        v-if="errors.length > 0"
        id="new-folder-errors"
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
          {{ t("new_folder.cancel") }}
        </button>
        <button
          type="submit"
          class="btn btn-primary"
          :disabled="submitting"
        >
          {{ t("new_folder.submit") }}
        </button>
      </div>
    </form>
  </dialog>
</template>
