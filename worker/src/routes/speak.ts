import { charge } from "../budget";
import {
  maxRetryWaitMs,
  readBody,
  requireSecret,
  retryAfterFrom,
  sleep,
  unavailable,
  upstreamFailure,
} from "../http";
import { settings } from "../settings";
import { obj, str, ValidationError, type Validator } from "../validate";

export const speech = {
  endpoint: "https://api.elevenlabs.io/v1/text-to-speech",
  model: "eleven_v4_turbo",
  outputFormat: "mp3_44100_64",
  contentType: "audio/mpeg",
  maxCharacters: 400,
  settings: { stability: 0.6, similarity_boost: 0.75 },
} as const;

export type Deadlines = { fetchMs: number; stallMs: number };

/** A 400-character line renders in a few seconds: 20 s for the whole call, 10 s for any gap in the audio. */
export const deadlines: Deadlines = { fetchMs: 20_000, stallMs: 10_000 };

const retryDelayMs = 250;

const line: Validator<string> = (v, p) => {
  const text = str(v, p);
  if (text.trim().length === 0 || text.length > speech.maxCharacters) {
    throw new ValidationError(p, `1 to ${speech.maxCharacters} characters`);
  }
  return text;
};

const body = obj({ text: line });

const isTimeout = (e: unknown) => e instanceof DOMException && e.name === "TimeoutError";

const synthesize = async (apiKey: string, voice: string, text: string, fetchMs: number) => {
  const url = `${speech.endpoint}/${encodeURIComponent(voice)}/stream?output_format=${speech.outputFormat}`;
  try {
    return await fetch(url, {
      method: "POST",
      headers: { "xi-api-key": apiKey, "content-type": "application/json" },
      body: JSON.stringify({ text, model_id: speech.model, voice_settings: speech.settings }),
      signal: AbortSignal.timeout(fetchMs),
    });
  } catch (e) {
    if (isTimeout(e)) throw unavailable("elevenlabs", 1);
    throw e;
  }
};

const upstreamError = async (res: Response): Promise<never> => {
  throw upstreamFailure("elevenlabs", res.status, res.headers.get("retry-after"), await res.text());
};

/** Passes the audio through and errors the client stream when no chunk arrives within `stallMs`. */
const watched = (audio: ReadableStream<Uint8Array>, stallMs: number) => {
  const reader = audio.getReader();
  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const stalled = new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new DOMException("audio stalled", "TimeoutError")),
          stallMs,
        );
      });
      try {
        const { done, value } = await Promise.race([reader.read(), stalled]);
        if (done) controller.close();
        else controller.enqueue(value);
      } catch (e) {
        await reader.cancel(e).catch(() => undefined);
        controller.error(e);
      } finally {
        clearTimeout(timer);
      }
    },
    cancel: (reason) => reader.cancel(reason),
  });
};

export const speakWith =
  ({ fetchMs, stallMs }: Deadlines) =>
  async (request: Request, env: Env, device: string): Promise<Response> => {
    const { text } = await readBody(request, body);
    const apiKey = requireSecret(env.ELEVENLABS_API_KEY, "ELEVENLABS_API_KEY");
    const { voiceId: voice } = settings(env);

    let res = await synthesize(apiKey, voice, text, fetchMs);
    if (res.status === 429) {
      const header = res.headers.get("retry-after");
      const waitMs = header ? retryAfterFrom(header) * 1000 : retryDelayMs;
      if (waitMs > maxRetryWaitMs) return upstreamError(res);
      await res.body?.cancel();
      await sleep(waitMs);
      res = await synthesize(apiKey, voice, text, fetchMs);
    }
    if (!res.ok) return upstreamError(res);

    const characters = Number(res.headers.get("x-character-count")) || text.length;
    await charge(env, device, "elevenlabs", characters);
    const headers: Record<string, string> = {
      "content-type": speech.contentType,
      "cache-control": "no-store",
      "x-character-count": String(characters),
    };
    const requestId = res.headers.get("request-id");
    if (requestId) headers["request-id"] = requestId;
    return new Response(res.body && watched(res.body, stallMs), { headers });
  };

export const speak = speakWith(deadlines);
