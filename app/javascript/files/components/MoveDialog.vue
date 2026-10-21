<script setup lang="ts">
import { computed, ref, shallowRef } from "vue"
import { api, ForbiddenError, ValidationError, type FolderLink, type FolderPayload, type FolderSource } from "../api"
import { t } from "../i18n"
import FileIcon from "./FileIcon.vue"

type Item = { id: number, name: string }

// 移動先を選ぶ。今いるフォルダから始め、フォルダをたどって選ぶ。
// location が null のときは、ドライブ（組織共有ドライブ・マイドライブ）を選ぶ段にいる
const props = defineProps<{ from: FolderLink }>()
const emit = defineEmits<{ moved: [] }>()

const dialog = ref<HTMLDialogElement | null>(null)
const items = shallowRef<Item[]>([])
const location = shallowRef<FolderPayload | null>(null)
const errors = ref<string[]>([])
const busy = ref(false)

const title = computed(() =>
  items.value.length === 1
    ? t("move.title_one", { name: items.value[0].name })
    : t("move.title_other", { count: items.value.length }),
)
const folders = computed(() => location.value?.entries.filter((entry) => entry.kind === "folder") ?? [])
const moving = (id: number) => items.value.some((item) => item.id === id)
const canSubmit = computed(() =>
  !busy.value && location.value !== null && location.value.can_edit && location.value.folder.id !== props.from.id,
)

const show = async (source: FolderSource | null) => {
  errors.value = []
  if (source === null) {
    location.value = null
    return
  }
  busy.value = true
  try {
    location.value = await api.folder(source)
  } catch (error) {
    errors.value = [t("move.failed")]
    console.error(error)
  } finally {
    busy.value = false
  }
}

// 閲覧できる祖先が無ければ（共有されたフォルダから始めた場合など）、ドライブを選ぶ段へ戻る
const up = () => {
  const parent = location.value?.breadcrumbs.at(-1)
  show(parent ? { id: String(parent.id) } : null)
}

const open = async (selected: Item[]) => {
  items.value = selected
  dialog.value?.showModal()
  await show({ id: String(props.from.id) })
}

const close = () => dialog.value?.close()

const submit = async () => {
  if (!canSubmit.value || location.value === null) return
  busy.value = true
  try {
    await api.move(items.value.map((item) => item.id), location.value.folder.id)
    close()
    emit("moved")
  } catch (error) {
    if (error instanceof ValidationError) errors.value = error.messages
    else if (error instanceof ForbiddenError) errors.value = [t("move.forbidden")]
    else {
      errors.value = [t("move.failed")]
      console.error(error)
    }
  } finally {
    busy.value = false
  }
}

defineExpose({ open })
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="move-title"
    class="m-auto w-[calc(100%-2rem)] max-w-lg rounded-2xl bg-white p-6 text-slate-800 shadow-xl backdrop:bg-slate-900/40"
  >
    <h2
      id="move-title"
      class="truncate text-lg font-medium"
    >
      {{ title }}
    </h2>

    <div class="mt-4 flex items-center gap-1 text-sm">
      <button
        v-if="location"
        type="button"
        class="cursor-pointer rounded-full p-1.5 text-slate-500 hover:bg-slate-900/5"
        :aria-label="t('move.up')"
        @click="up"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          class="size-4"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M15 6l-6 6 6 6"
          />
        </svg>
      </button>
      <span
        id="move-location"
        class="truncate px-1 font-medium"
      >{{ location ? location.folder.label : t("move.drives") }}</span>
    </div>

    <ul
      class="mt-2 h-64 overflow-y-auto rounded-xl border border-slate-200 py-1"
      aria-labelledby="move-location"
    >
      <template v-if="location === null">
        <li>
          <button
            type="button"
            class="flex w-full cursor-pointer items-center gap-2 px-4 py-2 text-left text-sm hover:bg-canvas"
            @click="show({ drive: 'shared' })"
          >
            <FileIcon folder />
            {{ t("sections.shared_drive") }}
          </button>
        </li>
        <li>
          <button
            type="button"
            class="flex w-full cursor-pointer items-center gap-2 px-4 py-2 text-left text-sm hover:bg-canvas"
            @click="show({ drive: 'mine' })"
          >
            <FileIcon folder />
            {{ t("sections.my_drive") }}
          </button>
        </li>
      </template>
      <template v-else>
        <li
          v-for="folder in folders"
          :key="folder.id"
        >
          <!-- 移すフォルダの中や、開けないフォルダへは入れない -->
          <button
            type="button"
            class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm enabled:cursor-pointer enabled:hover:bg-canvas disabled:text-slate-400"
            :disabled="moving(folder.id) || !folder.readable"
            :aria-label="t('move.open', { name: folder.name })"
            @click="show({ id: String(folder.id) })"
          >
            <FileIcon folder />
            <span class="truncate">{{ folder.name }}</span>
            <span
              v-if="moving(folder.id)"
              class="ml-auto shrink-0 text-xs"
            >{{ t("move.moving") }}</span>
          </button>
        </li>
        <li
          v-if="folders.length === 0"
          class="px-4 py-8 text-center text-sm text-slate-500"
        >
          {{ t("move.no_folders") }}
        </li>
      </template>
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

    <div class="mt-6 flex justify-end gap-2">
      <button
        type="button"
        class="btn btn-secondary"
        @click="close"
      >
        {{ t("move.cancel") }}
      </button>
      <button
        type="button"
        class="btn btn-primary disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!canSubmit"
        @click="submit"
      >
        {{ t("move.submit") }}
      </button>
    </div>
  </dialog>
</template>
