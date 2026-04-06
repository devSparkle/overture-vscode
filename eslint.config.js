import js from "@eslint/js"
import globals from "globals"
import tseslint from "typescript-eslint"
import { defineConfig } from "eslint/config"


export default defineConfig([
	{ files: ["**/*.{js,mjs,cjs,ts}"], plugins: { js }, extends: ["js/recommended"] },
	{ files: ["**/*.{js,mjs,cjs,ts}"], languageOptions: { globals: globals.node } },
	tseslint.configs.recommended,

	{
		rules: {
			"no-extra-semi": "warn",
			"semi": ["warn", "never"],
			"indent": ["warn", "tab", { ignoreComments: true, SwitchCase: 1 }],
			
			// Prevents duplicate warnings
			"no-unused-vars": "off",
			"@typescript-eslint/no-unused-vars": "warn",
		}
	}
])