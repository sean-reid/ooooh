import { ElevenLabsClient, ElevenLabsError } from "@elevenlabs/elevenlabs-js";
import { charge } from "../budget";
import { HttpError, maxRetryWaitMs, readBody, requireSecret, retryAfterFrom, sleep } from "../http";
import { obj, str, ValidationError, type Validator } from "../validate";

export const speech = {
  model: "eleven_v4_turbo",
  outputFormat: "mp3_44100_64",
  contentType: "audio/mpeg",
  maxCharacters: 400,
  settings: { stability: 0.6, similarityBoost: 0.75 },
} as const;

const retryDelayMs = 250;

const line: Validator<string> = (v, p) => {
  const text = str(v, p);
  if (text.trim().length === 0 || text.length > speech.maxCharacters) {
    throw new ValidationError(p, `1 to ${speech.maxCharacters} characters`);
  }
  return text;
};

const body = obj({ text: line });

const retryAfterSeconds = (e: ElevenLabsError) =>
  retryAfterFrom(e.rawResponse?.headers.get("retry-after"));

const upstreamError = (e: unknown): never => {
  if (!(e instanceof ElevenLabsError)) throw e;
  if (e.statusCode === 429) {
    throw new HttpError(503, { error: "elevenlabs unavailable", retryAfter: retryAfterSeconds(e) });
  }
  throw new HttpError(502, {
    error: "elevenlabs",
    status: e.statusCode,
    detail: e.message.slice(0, 500),
  });
};

const synthesize = (client: ElevenLabsClient, voice: string, text: string) =>
  client.textToSpeech
    .stream(
      voice,
      {
        text,
        modelId: speech.model,
        outputFormat: speech.outputFormat,
        voiceSettings: speech.settings,
      },
      { maxRetries: 0 },
    )
    .withRawResponse();

export async function speak(request: Request, env: Env): Promise<Response> {
  const { text } = await readBody(request, body);
  const apiKey = requireSecret(env.ELEVENLABS_API_KEY, "ELEVENLABS_API_KEY");
  const voice = requireSecret(env.ELEVENLABS_VOICE_ID, "ELEVENLABS_VOICE_ID");
  const client = new ElevenLabsClient({ apiKey, timeoutInSeconds: 30 });

  const { data, rawResponse } = await synthesize(client, voice, text).catch(async (e: unknown) => {
    if (!(e instanceof ElevenLabsError) || e.statusCode !== 429) return upstreamError(e);
    const header = e.rawResponse?.headers.get("retry-after");
    const waitMs = header ? retryAfterFrom(header) * 1000 : retryDelayMs;
    if (waitMs > maxRetryWaitMs) return upstreamError(e);
    await sleep(waitMs);
    return synthesize(client, voice, text).catch(upstreamError);
  });

  const characters = Number(rawResponse.headers.get("x-character-count")) || text.length;
  await charge(env, "elevenlabs", characters);
  const headers: Record<string, string> = {
    "content-type": speech.contentType,
    "cache-control": "no-store",
    "x-character-count": String(characters),
  };
  const requestId = rawResponse.headers.get("request-id");
  if (requestId) headers["request-id"] = requestId;
  return new Response(data, { headers });
}
