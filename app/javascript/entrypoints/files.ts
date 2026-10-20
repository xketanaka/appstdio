import { createApp } from "vue"
import App from "~/files/App.vue"
import { router } from "~/files/router"
import { loadConfig } from "~/files/store"

const element = document.getElementById("files-app")
if (element) {
  loadConfig(element)
  createApp(App).use(router).mount(element)
}
