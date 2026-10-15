import js from "@eslint/js"
import stylistic from "@stylistic/eslint-plugin"
import { defineConfig } from "eslint/config"
import pluginVue from "eslint-plugin-vue"
import globals from "globals"
import tseslint from "typescript-eslint"

export default defineConfig(
  { ignores: ["coverage/", "log/", "public/", "tmp/", "vendor/"] },
  js.configs.recommended,
  tseslint.configs.recommended,
  pluginVue.configs["flat/essential"],
  {
    files: ["**/*.vue"],
    languageOptions: { parserOptions: { parser: tseslint.parser } },
  },
  {
    languageOptions: { globals: globals.browser },
    rules: {
      // Tree.vue のような1語の名前を許す
      "vue/multi-word-component-names": "off",
    },
  },
  stylistic.configs.customize({ quotes: "double", semi: false, arrowParens: true, braceStyle: "1tbs" }),
)
