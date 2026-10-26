import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Stand-ins so the workers project never reaches a real provider. Real keys stay in .dev.vars for the node project.
// Attestation is off here like local dev; the attest suites turn it on per request with their own root.
const testSecrets = {
  TYPESAFE_API_KEY: "test-jev",
  ANTHROPIC_API_KEY: "test-anthropic",
  ELEVENLABS_API_KEY: "test-elevenlabs",
  ANTHROPIC_AUTH_TOKEN: "",
  REQUIRE_ATTESTATION: "false",
  APP_ATTEST_ENVIRONMENT: "production",
};

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      include: ["src/**"],
      reporter: ["text", "json-summary"],
      // dist/ is already gitignored.
      reportsDirectory: "dist/coverage",
    },
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
        resolve: { alias: { "cloudflare:workers": "./test/node/cloudflare-workers.ts" } },
      },
    ],
  },
});
