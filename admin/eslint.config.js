import eslint from "@eslint/js";
import eslintConfigPrettier from "eslint-config-prettier";
import pluginVue from "eslint-plugin-vue";
import tseslint from "typescript-eslint";
import vueParser from "vue-eslint-parser";

export default tseslint.config(
  { ignores: ["dist/**", "node_modules/**"] },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  ...pluginVue.configs["flat/recommended"],
  {
    files: ["**/*.vue"],
    languageOptions: {
      parser: vueParser,
      parserOptions: { parser: tseslint.parser, extraFileExtensions: [".vue"] },
    },
  },
  {
    languageOptions: {
      globals: {
        Event: "readonly",
        KeyboardEvent: "readonly",
        Blob: "readonly",
        URL: "readonly",
        localStorage: "readonly",
        sessionStorage: "readonly",
        location: "readonly",
        structuredClone: "readonly",
        File: "readonly",
        FormData: "readonly",
        HTMLInputElement: "readonly",
        URLSearchParams: "readonly",
        fetch: "readonly",
        window: "readonly",
        document: "readonly",
      },
    },
  },
  {
    // 演示用的本地 mock 服务（Node 环境），不进入生产构建。
    files: ["mock/**/*.mjs"],
    languageOptions: { globals: { process: "readonly", console: "readonly" } },
  },
  eslintConfigPrettier,
  {
    rules: {
      "vue/multi-word-component-names": "off",
      // 可选 prop 在 TS 里本来就是 undefined，不需要再写默认值。
      "vue/require-default-prop": "off",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    },
  },
);
