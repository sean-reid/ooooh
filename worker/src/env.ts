// The bindings and vars come from worker-configuration.d.ts, which `npm run types` writes from
// wrangler.jsonc; the vars are read through settings.ts. Secrets and test roots are declared here.
declare global {
  interface Env {
    TYPESAFE_API_KEY?: string;
    ANTHROPIC_API_KEY?: string;
    ANTHROPIC_AUTH_TOKEN?: string;
    ELEVENLABS_API_KEY?: string;
    /** Test roots; a deployment verifies against Apple's. */
    APP_ATTEST_ROOT_PEM?: string;
    APPLE_ROOT_PEM?: string;
  }
}

export {};
