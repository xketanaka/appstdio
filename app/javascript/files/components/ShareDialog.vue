<script setup lang="ts">
import { computed, reactive, ref, shallowRef, watch } from "vue"
import { api, type InheritedSetting, type Role, type ShareCandidate, type SharingChange, type Subject } from "../api"
import { t } from "../i18n"
import { changed, notify, operationErrorMessages, state } from "../store"
import SubjectIcon from "./SubjectIcon.vue"

// 共有設定。行のメニューかフォルダの「共有」で state.sharingOf が入ると開く。
// 変えた内容は手元に溜め、「保存する」で開いたときからの差分だけを送る
const ROLES: Role[] = ["viewer", "editor", "manager"]

const dialog = ref<HTMLDialogElement | null>(null)
const inherited = shallowRef<InheritedSetting[]>([])
const own = ref<{ subject: Subject, role: Role }[]>([])
const cancelled = reactive(new Set<string>())
// 開いたときのこのもの自身の設定。打ち消しは "none"
let initial = new Map<string, Role | "none">()
const errors = ref<string[]>([])
const submitting = ref(false)

const query = ref("")
const candidates = shallowRef<ShareCandidate[]>([])
let searchTimer: ReturnType<typeof setTimeout> | undefined
const searchInput = ref<HTMLInputElement | null>(null)

const keyOf = (subject: Pick<Subject, "type" | "id">) => `${subject.type}:${subject.id}`

watch(() => state.sharingOf, async (target) => {
  inherited.value = []
  own.value = []
  cancelled.clear()
  errors.value = []
  query.value = ""
  candidates.value = []
  if (!target) return
  dialog.value?.showModal()
  // 検索欄ではなくダイアログにフォーカスを当てる
  dialog.value?.focus()
  try {
    const loaded = await api.sharing(target.id)
    inherited.value = loaded.inherited
    own.value = loaded.own.map((setting) => ({ ...setting }))
    loaded.inherited.filter((setting) => setting.cancelled).forEach((setting) => cancelled.add(keyOf(setting.subject)))
    initial = new Map([
      ...loaded.own.map((setting) => [keyOf(setting.subject), setting.role] as const),
      ...[...cancelled].map((key) => [key, "none"] as const),
    ])
  } catch (error) {
    notify(operationErrorMessages("share", error).join(" "), { error: true })
    close()
  }
})

const close = () => {
  dialog.value?.close()
  state.sharingOf = null
}

// 打ち消すと、同じ相手へのこのもの自身の設定は消える（1つの相手に設定は1つ）
const toggleCancel = (subject: Subject) => {
  const key = keyOf(subject)
  if (cancelled.has(key)) {
    cancelled.delete(key)
  } else {
    cancelled.add(key)
    own.value = own.value.filter((setting) => keyOf(setting.subject) !== key)
  }
}

const remove = (subject: Subject) => {
  own.value = own.value.filter((setting) => keyOf(setting.subject) !== keyOf(subject))
}

const add = (candidate: ShareCandidate) => {
  const subject: Subject = {
    type: candidate.type, id: candidate.id, name: candidate.name, everyone: candidate.everyone, suspended: false,
    deleted: false, path: candidate.path,
  }
  cancelled.delete(keyOf(subject))
  own.value.push({ subject, role: "viewer" })
  query.value = ""
  candidates.value = []
}

const search = () => {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(async () => {
    try {
      const found = await api.shareCandidates(query.value)
      if (document.activeElement !== searchInput.value) return
      const added = new Set(own.value.map((setting) => keyOf(setting.subject)))
      candidates.value = found.candidates.filter((candidate) => !added.has(keyOf(candidate)))
    } catch (error) {
      errors.value = operationErrorMessages("share", error)
    }
  }, 250)
}

const changes = computed<SharingChange[]>(() => {
  const current = new Map<string, Role | "none">([
    ...[...cancelled].map((key) => [key, "none"] as const),
    ...own.value.map((setting) => [keyOf(setting.subject), setting.role] as const),
  ])
  return [...new Set([...initial.keys(), ...current.keys()])]
    .filter((key) => initial.get(key) !== current.get(key))
    .map((key) => {
      const [type, id] = key.split(":")
      return { subject_type: type as Subject["type"], subject_id: Number(id), role: current.get(key) ?? null }
    })
})

const submit = async () => {
  const target = state.sharingOf
  if (submitting.value || !target) return
  if (changes.value.length === 0) {
    close()
    return
  }
  submitting.value = true
  try {
    await api.updateSharing(target.id, changes.value)
    close()
    notify(t("share.saved", { name: target.name }))
    await changed()
  } catch (error) {
    errors.value = operationErrorMessages("share", error)
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="share-title"
    tabindex="-1"
    class="m-auto outline-none w-[calc(100%-2rem)] max-w-xl rounded-2xl bg-white p-6 text-slate-800 shadow-xl backdrop:bg-slate-900/40"
    @close="state.sharingOf = null"
  >
    <form @submit.prevent="submit">
      <h2
        id="share-title"
        class="truncate text-lg font-medium"
      >
        {{ t("share.title", { name: state.sharingOf?.name ?? "" }) }}
      </h2>

      <section
        aria-labelledby="share-own"
        class="mt-4"
      >
        <h3
          id="share-own"
          class="text-sm font-medium text-slate-500"
        >
          {{ t(state.sharingOf?.kind === "file" ? "share.own_file" : "share.own_folder") }}
        </h3>

        <div
          class="relative mt-2"
          @focusout="!($event.currentTarget as Element).contains($event.relatedTarget as Node) && (candidates = [])"
        >
          <label
            for="share-search"
            class="sr-only"
          >{{ t("share.search_label") }}</label>
          <input
            id="share-search"
            ref="searchInput"
            v-model="query"
            type="search"
            autocomplete="off"
            class="input"
            :placeholder="t('share.search')"
            @input="search"
            @focus="search"
          >
          <ul
            v-if="candidates.length > 0"
            :aria-label="t('share.candidates')"
            class="absolute inset-x-0 z-10 mt-1 max-h-60 overflow-y-auto rounded-xl bg-white py-1.5 text-sm shadow-lg ring-1 ring-slate-900/10"
          >
            <li
              v-for="candidate in candidates"
              :key="keyOf(candidate)"
            >
              <button
                type="button"
                class="flex w-full cursor-pointer items-center gap-3 px-4 py-2 text-left hover:bg-slate-100"
                :title="candidate.path?.join(' / ')"
                @click="add(candidate)"
              >
                <SubjectIcon :subject="candidate" />
                <span class="min-w-0">
                  <span class="block truncate font-medium">{{ candidate.name }}</span>
                  <span
                    v-if="candidate.detail"
                    class="block truncate text-xs text-slate-500"
                  >{{ candidate.detail }}</span>
                </span>
              </button>
            </li>
          </ul>
        </div>

        <ul class="mt-2">
          <li
            v-for="setting in own"
            :key="keyOf(setting.subject)"
            class="flex items-center gap-3 py-1.5 text-sm"
          >
            <SubjectIcon :subject="setting.subject" />
            <div class="flex min-w-0 flex-1 items-center gap-2">
              <span
                class="truncate font-medium"
                :title="setting.subject.path?.join(' / ')"
              >{{ setting.subject.name }}</span>
              <span
                v-if="setting.subject.suspended"
                class="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-900"
              >{{ t("share.suspended") }}</span>
              <span
                v-else-if="setting.subject.deleted"
                class="shrink-0 rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
              >{{ t("share.deleted") }}</span>
            </div>
            <select
              v-model="setting.role"
              class="input w-28 shrink-0 py-1"
              :aria-label="t('share.role', { name: setting.subject.name })"
            >
              <option
                v-for="role in ROLES"
                :key="role"
                :value="role"
              >
                {{ t(`share.roles.${role}`) }}
              </option>
            </select>
            <button
              type="button"
              class="shrink-0 cursor-pointer rounded-full p-2 text-slate-600 hover:bg-slate-900/5"
              :aria-label="t('share.remove', { name: setting.subject.name })"
              :title="t('share.remove', { name: setting.subject.name })"
              @click="remove(setting.subject)"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                class="size-4"
                aria-hidden="true"
              >
                <path d="M6 6l12 12M18 6L6 18" />
              </svg>
            </button>
          </li>
        </ul>
      </section>

      <section
        v-if="inherited.length > 0"
        aria-labelledby="share-inherited"
        class="mt-5"
      >
        <h3
          id="share-inherited"
          class="text-sm font-medium text-slate-500"
        >
          {{ t("share.inherited") }}
        </h3>
        <ul class="mt-1">
          <li
            v-for="setting in inherited"
            :key="keyOf(setting.subject)"
            class="flex items-center gap-3 py-1.5 text-sm"
          >
            <SubjectIcon :subject="setting.subject" />
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span
                  class="truncate font-medium"
                  :title="setting.subject.path?.join(' / ')"
                >{{ setting.subject.name }}</span>
                <span
                  v-if="setting.subject.suspended"
                  class="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-900"
                >{{ t("share.suspended") }}</span>
                <span
                  v-else-if="setting.subject.deleted"
                  class="shrink-0 rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
                >{{ t("share.deleted") }}</span>
              </div>
              <p class="truncate text-xs text-slate-500">
                {{ setting.from ? t("share.from", { name: setting.from.label }) : t("share.from_hidden") }}
              </p>
            </div>
            <span
              class="w-28 shrink-0 px-3"
              :class="cancelled.has(keyOf(setting.subject)) ? 'text-slate-400' : 'text-slate-700'"
            >
              {{ cancelled.has(keyOf(setting.subject)) ? t("share.cancelled") : t(`share.roles.${setting.role}`) }}
            </span>
            <button
              type="button"
              class="shrink-0 cursor-pointer rounded-full p-2 text-slate-600 hover:bg-slate-900/5"
              :aria-label="t(cancelled.has(keyOf(setting.subject)) ? 'share.uncancel' : 'share.cancel_inherited', { name: setting.subject.name })"
              :title="t(cancelled.has(keyOf(setting.subject)) ? 'share.uncancel' : 'share.cancel_inherited', { name: setting.subject.name })"
              @click="toggleCancel(setting.subject)"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="size-4"
                aria-hidden="true"
              >
                <path
                  v-if="cancelled.has(keyOf(setting.subject))"
                  d="M4 12a8 8 0 1 0 2.3-5.7M4 4v4h4"
                />
                <path
                  v-else
                  d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM5.6 5.6l12.8 12.8"
                />
              </svg>
            </button>
          </li>
        </ul>
      </section>

      <ul
        v-if="errors.length > 0"
        role="alert"
        class="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"
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
          {{ t("share.cancel") }}
        </button>
        <button
          type="submit"
          class="btn btn-primary"
          :disabled="submitting"
        >
          {{ t("share.save") }}
        </button>
      </div>
    </form>
  </dialog>
</template>
