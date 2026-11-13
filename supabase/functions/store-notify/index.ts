// App Store Server Notifications V2: a verified REFUND or REVOKE takes the purchase back (unspent gold and boxes
// are removed, the rest becomes a debt). Set this function's URL in App Store Connect for production and sandbox.
import { APPLE_ROOT_CA_G3_SHA256, verifyAppleJWS } from "../_shared/apple_jws.ts";

const env = (k: string): string => Deno.env.get(k) ?? "";
const BUNDLE_ID = "com.matasdovyda.ledger";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return new Response("", { status: 405 });
  const body = await req.json().catch(() => null);
  const signed: unknown = body?.signedPayload;
  if (typeof signed !== "string" || signed.length > 50000) return new Response("", { status: 400 });
  const pin = env("APPLE_ROOT_CA_G3_SHA256") || APPLE_ROOT_CA_G3_SHA256;
  let note: Record<string, any>;
  try {
    note = await verifyAppleJWS(signed, { rootSha256: pin });
  } catch {
    return new Response("", { status: 400 });
  }
  const type = String(note.notificationType ?? "");
  const data = note.data ?? {};
  if (data.bundleId !== BUNDLE_ID || (type !== "REFUND" && type !== "REVOKE") || typeof data.signedTransactionInfo !== "string") {
    return new Response("", { status: 200 });
  }
  let tx: Record<string, unknown>;
  try {
    tx = await verifyAppleJWS(data.signedTransactionInfo, { rootSha256: pin });
  } catch {
    return new Response("", { status: 400 });
  }
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  const rpc = await fetch(`${env("SUPABASE_URL")}/rest/v1/rpc/revoke_purchase`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_original_transaction_id: String(tx.originalTransactionId ?? ""), p_product_id: String(tx.productId ?? ""), p_tx: tx }),
  });
  // Apple retries anything but 200, so a database failure is reported as one.
  return new Response("", { status: rpc.ok ? 200 : 500 });
});
