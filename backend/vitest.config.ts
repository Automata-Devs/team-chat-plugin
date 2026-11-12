import { defineConfig } from "vitest/config";

export default defineConfig({
	test: {
		globalSetup: ["./test/globalSetup.ts"],
		include: ["test/**/*.test.ts"],
		pool: "forks",
		maxWorkers: 4,
		testTimeout: 30_000,
		hookTimeout: 120_000,
	},
});
