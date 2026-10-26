// Signed transactions in Apple's JWS layout from a chain made here: a P-384 root and intermediate
// carrying Apple's marker extensions and a P-256 receipt signing leaf.
import worker from "../src/index";
import { appAccountTokenFor } from "../src/entitlement";
import { toBase64, type Bytes } from "../src/bytes";
import { certificate, generate, octets, oid, pem, seq, tlv, type Authority } from "./x509";

export interface StoreChain {
  rootPem: string;
  rootDer: Bytes;
  intermediateDer: Bytes;
  leafDer: Bytes;
  leaf: CryptoKeyPair;
}

export const day = 86_400_000;
export const leafMarker = "1.2.840.113635.100.6.11.1";
export const intermediateMarker = "1.2.840.113635.100.6.2.1";

/** Apple's markers carry no value, so the extension body is a DER NULL. */
const marker = (id: string) => seq(oid(id), octets(tlv(0x05, [])));

interface ChainOptions {
  leafMarker?: string;
  intermediateMarker?: string;
  leafNotBefore?: Date;
  leafNotAfter?: Date;
}

export async function makeStoreChain(options: ChainOptions = {}): Promise<StoreChain> {
  const root: Authority = {
    name: "Test Apple Root CA - G3",
    curve: "P-384",
    keys: await generate("P-384"),
  };
  const intermediate: Authority = {
    name: "Test Worldwide Developer Relations CA",
    curve: "P-384",
    keys: await generate("P-384"),
  };
  const leaf = await generate("P-256");
  const rootDer = await certificate({
    subject: root.name,
    publicKey: root.keys.publicKey,
    issuer: root,
  });
  const intermediateDer = await certificate({
    subject: intermediate.name,
    publicKey: intermediate.keys.publicKey,
    issuer: root,
    extensions: [marker(options.intermediateMarker ?? intermediateMarker)],
  });
  const leafDer = await certificate({
    subject: "Test Receipt Signing",
    publicKey: leaf.publicKey,
    issuer: intermediate,
    extensions: [marker(options.leafMarker ?? leafMarker)],
    notBefore: options.leafNotBefore,
    notAfter: options.leafNotAfter,
  });
  return { rootPem: pem(rootDer), rootDer, intermediateDer, leafDer, leaf };
}

/** A monthly subscription bought today, in the shape of `JWSTransactionDecodedPayload`. */
export const transactionPayload = (now: number, overrides: Record<string, unknown> = {}) => ({
  transactionId: "2000000123456789",
  originalTransactionId: "2000000123456000",
  webOrderLineItemId: "2000000012345678",
  bundleId: "com.seanreid.ooooh",
  productId: "com.seanreid.ooooh.monthly",
  subscriptionGroupIdentifier: "21500000",
  purchaseDate: now,
  originalPurchaseDate: now,
  expiresDate: now + 30 * day,
  quantity: 1,
  type: "Auto-Renewable Subscription",
  inAppOwnershipType: "PURCHASED",
  signedDate: now,
  environment: "Production",
  transactionReason: "PURCHASE",
  storefront: "USA",
  storefrontId: "143441",
  price: 4990,
  currency: "USD",
  ...overrides,
});

const base64Url = (bytes: Bytes) =>
  toBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encodePart = (value: unknown) => base64Url(new TextEncoder().encode(JSON.stringify(value)));

interface SignOptions {
  /** Signs with another key, for a forged case. */
  signer?: CryptoKey;
  alg?: string;
  x5c?: Bytes[];
}

export async function signTransaction(
  chain: StoreChain,
  payload: Record<string, unknown>,
  options: SignOptions = {},
): Promise<string> {
  const x5c = options.x5c ?? [chain.leafDer, chain.intermediateDer, chain.rootDer];
  const header = { alg: options.alg ?? "ES256", x5c: x5c.map(toBase64) };
  const input = `${encodePart(header)}.${encodePart(payload)}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      options.signer ?? chain.leaf.privateKey,
      new TextEncoder().encode(input),
    ),
  );
  return `${input}.${base64Url(signature)}`;
}

/** Buys a month for `device` through the route, with attestation off and this chain as Apple's root. */
export async function buyMonth(device: string, chain: StoreChain, env: Env, now = Date.now()) {
  const payload = transactionPayload(now, { appAccountToken: await appAccountTokenFor(device) });
  const transaction = await signTransaction(chain, payload);
  return worker.fetch(
    new Request("https://ooooh.test/v1/entitlement", {
      method: "POST",
      headers: { "content-type": "application/json", "x-device": device },
      body: JSON.stringify({ transaction }),
    }),
    { ...env, REQUIRE_ATTESTATION: "false", APPLE_ROOT_PEM: chain.rootPem },
  );
}
