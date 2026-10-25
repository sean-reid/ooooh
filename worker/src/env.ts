declare global {
  interface Env {
    BUDGET: KVNamespace;
    TYPESAFE_API_KEY?: string;
    ANTHROPIC_API_KEY?: string;
    ANTHROPIC_AUTH_TOKEN?: string;
    ELEVENLABS_API_KEY?: string;
    JEV_DAILY_TOKENS?: string;
    ANTHROPIC_DAILY_TOKENS?: string;
    ELEVENLABS_DAILY_CHARACTERS?: string;
    DEVICE_MINUTE_REQUESTS?: string;
  }
}

export {};
