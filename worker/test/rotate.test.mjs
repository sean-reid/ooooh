import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import process from "node:process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const root = realpathSync(resolve(fileURLToPath(import.meta.url), "../../.."));
const script = join(root, "bin", "rotate-secret");
const value = "sk-rotated-9f3a";

const run = (args, { stdin = "", env = {} } = {}) =>
  new Promise((done) => {
    const child = spawn("sh", [script, ...args], { env: { ...process.env, ...env } });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("close", (code) => done({ code, stdout, stderr }));
    // The script reads stdin only on its tty-less path; a run that exits first closes the pipe under us.
    child.stdin.on("error", () => {});
    child.stdin.end(stdin);
  });

const serve = (routeStatus) =>
  new Promise((ready) => {
    const seen = [];
    const server = createServer((req, res) => {
      let body = "";
      req.on("data", (d) => (body += d));
      req.on("end", () => {
        seen.push({ method: req.method, url: req.url, body });
        res.statusCode = req.url === "/health" ? 200 : routeStatus;
        res.end();
      });
    });
    server.listen(0, "127.0.0.1", () => {
      const api = `http://127.0.0.1:${server.address().port}`;
      ready({ seen, api, close: () => server.close() });
    });
  });

test("parses as POSIX sh", async () => {
  const check = await new Promise((done) => spawn("sh", ["-n", script]).on("close", done));
  assert.equal(check, 0);
});

test("refuses a missing, unknown, or empty value", async () => {
  const none = await run([]);
  assert.equal(none.code, 2);
  assert.match(none.stderr, /^usage: bin\/rotate-secret/);
  const unknown = await run(["CLOUDFLARE_API_TOKEN"], { stdin: value });
  assert.equal(unknown.code, 2);
  assert.match(unknown.stderr, /^usage/);
  const empty = await run(["ELEVENLABS_API_KEY"], { stdin: "", env: { WRANGLER: "echo" } });
  assert.equal(empty.code, 2);
  assert.match(empty.stderr, /empty value/);
});

test("puts the secret in production and probes the route that uses it", async () => {
  const server = await serve(200);
  try {
    const { code, stdout, stderr } = await run(["ELEVENLABS_API_KEY"], {
      stdin: `${value}\n`,
      env: { WRANGLER: "echo", OOOOH_API: server.api },
    });
    assert.equal(code, 0, stderr);
    assert.deepEqual(stdout.trim().split("\n"), [
      "secret put ELEVENLABS_API_KEY --env production",
      "ok",
    ]);
    assert.ok(!stdout.includes(value) && !stderr.includes(value));
    assert.deepEqual(server.seen, [
      { method: "GET", url: "/health", body: "" },
      { method: "POST", url: "/v1/speak", body: '{"text":"ok"}' },
    ]);
    assert.match(stderr, /Revoke the old ELEVENLABS_API_KEY in the ElevenLabs console/);
    assert.match(stderr, /"KEY_ROTATED_AT_ELEVENLABS_API_KEY": "\d{4}-\d\d-\d\d"/);
  } finally {
    server.close();
  }
});

test("hands the value to wrangler on stdin from worker/", async () => {
  const dir = mkdtempSync(join(tmpdir(), "rotate-"));
  const stub = join(dir, "wrangler");
  const out = join(dir, "out");
  writeFileSync(stub, `#!/bin/sh\npwd > "$OUT"\nprintf '%s\\n' "$*" >> "$OUT"\ncat >> "$OUT"\n`);
  chmodSync(stub, 0o755);
  const server = await serve(200);
  try {
    const { code, stderr } = await run(["TYPESAFE_API_KEY"], {
      stdin: value,
      env: { WRANGLER: stub, OUT: out, OOOOH_API: server.api },
    });
    assert.equal(code, 0, stderr);
    assert.equal(
      readFileSync(out, "utf8"),
      `${join(root, "worker")}\nsecret put TYPESAFE_API_KEY --env production\n${value}`,
    );
    assert.equal(server.seen[1].url, "/v1/decide");
  } finally {
    server.close();
  }
});

test("prints the failing status and route", async () => {
  const server = await serve(502);
  try {
    const { code, stdout } = await run(["ANTHROPIC_API_KEY"], {
      stdin: value,
      env: { WRANGLER: "echo", OOOOH_API: server.api },
    });
    assert.equal(code, 1);
    assert.equal(stdout.trim().split("\n").pop(), "502 /v1/compact");
    assert.ok(!stdout.includes("ok"));
  } finally {
    server.close();
  }
});
