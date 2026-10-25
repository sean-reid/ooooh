export type Entitlement = "free" | "paid";

/** What the device is entitled to. Reads the App Store transaction once StoreKit lands. */
export const entitlement: (keyId: string, env: Env) => Promise<Entitlement> = async () => "free";
