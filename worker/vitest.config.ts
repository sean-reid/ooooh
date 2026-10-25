import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Stand-ins so tests never reach a real provider.
const testSecrets = { TYPESAFE_API_KEY: "test-jev", ANTHROPIC_API_KEY: "test-anthropic" };

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: { bindings: testSecrets },
    }),
  ],
});
