<script setup lang="ts">
import type { Subject } from "../api"

// 共有の相手の印。人はアバター（未設定なら画面右上と同じ人の絵）、グループと「全員」は絵で見分ける
defineProps<{ subject: Pick<Subject, "type" | "everyone" | "avatar_url"> }>()
</script>

<template>
  <img
    v-if="subject.type === 'tenant_user' && subject.avatar_url"
    :src="subject.avatar_url"
    alt=""
    loading="lazy"
    class="size-8 shrink-0 rounded-full bg-slate-100 object-cover"
  >
  <span
    v-else-if="subject.type === 'tenant_user'"
    class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-600 text-white"
    aria-hidden="true"
  >
    <svg
      viewBox="0 0 24 24"
      fill="currentColor"
      class="size-5/8"
    >
      <path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z" />
      <path d="M3.5 21.75a8.5 8.5 0 0 1 17 0 .75.75 0 0 1-.75.75H4.25a.75.75 0 0 1-.75-.75Z" />
    </svg>
  </span>
  <span
    v-else
    class="flex size-8 shrink-0 items-center justify-center rounded-full bg-slate-100 text-sm text-slate-600"
    aria-hidden="true"
  >
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      class="size-4"
    >
      <path
        v-if="subject.everyone"
        d="M4 21V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v16M16 9h2a2 2 0 0 1 2 2v10M2 21h20M8 7h4M8 11h4M8 15h4"
      />
      <path
        v-else
        d="M16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM8 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM2 20c0-3 2.7-5 6-5s6 2 6 5M14.5 15.2c.5-.1 1-.2 1.5-.2 3.3 0 6 2 6 5"
      />
    </svg>
  </span>
</template>
