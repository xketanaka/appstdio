import { createRouter, createWebHistory } from "vue-router"
import FolderPage from "./pages/FolderPage.vue"
import SharedItemsPage from "./pages/SharedItemsPage.vue"
import TrashPage from "./pages/TrashPage.vue"

// URL は config/routes.rb の files 以下と揃えること。直接開いたときはサーバがこの URL を受ける
export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: "/files", name: "shared_drive", component: FolderPage, props: { source: { drive: "shared" } } },
    { path: "/files/my_drive", name: "my_drive", component: FolderPage, props: { source: { drive: "mine" } } },
    { path: "/files/folders/:id", name: "folder", component: FolderPage, props: (route) => ({ source: { id: route.params.id } }) },
    { path: "/files/shared", name: "shared_with_me", component: SharedItemsPage },
    { path: "/files/trash", name: "trash", component: TrashPage },
  ],
})
