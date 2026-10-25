import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Stand-ins so the workers project never reaches a real provider. Real keys stay in .dev.vars for the node project.
const testSecrets = { TYPESAFE_API_KEY: "test-jev", ANTHROPIC_API_KEY: "test-anthropic" };

export default defineConfig({
  test: {
    projects: [
      {
        plugins: [
          cloudflareTest({
            wrangler: { configPath: "./wrangler.jsonc" },
            miniflare: { bindings: testSecrets },
          }),
        ],
        test: { name: "workers", include: ["test/*.test.ts"] },
      },
      {
        test: { name: "node", include: ["test/node/*.test.ts"], environment: "node" },
      },
    ],
  },
});
