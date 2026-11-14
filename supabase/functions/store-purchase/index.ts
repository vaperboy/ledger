// Delivers an App Store purchase to the signed-in player: verifies Apple's signature on the StoreKit 2 transaction,
// then lets grant_purchase pay it once per original transaction (or take it back when Apple revoked it).
import { APPLE_ROOT_CA_G3_SHA256, verifyAppleJWS } from "../_shared/apple_jws.ts";

const env = (k: string): string => Deno.env.get(k) ?? "";

const reply = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function userID(auth: string): Promise<string | null> {
  if (!auth.startsWith("Bearer ")) return null;
  const res = await fetch(`${env("SUPABASE_URL")}/auth/v1/user`, {
    headers: { apikey: env("SUPABASE_ANON_KEY") || env("SUPABASE_SERVICE_ROLE_KEY"), Authorization: auth },
  });
  if (!res.ok) return null;
  const user = await res.json();
  return typeof user?.id === "string" ? user.id : null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return reply({ message: "invalid_action" }, 405);
  const uid = await userID(req.headers.get("Authorization") ?? "");
  if (!uid) return reply({ message: "not_signed_in" }, 401);
  const body = await req.json().catch(() => null);
  const jws: unknown = body?.jws;
  if (typeof jws !== "string" || jws.length < 20 || jws.length > 20000) return reply({ message: "invalid_value" }, 400);
  let tx: Record<string, unknown>;
  try {
    tx = await verifyAppleJWS(jws, { rootSha256: env("APPLE_ROOT_CA_G3_SHA256") || APPLE_ROOT_CA_G3_SHA256 });
  } catch {
    return reply({ message: "invalid_receipt" }, 400);
  }
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  const rpc = await fetch(`${env("SUPABASE_URL")}/rest/v1/rpc/grant_purchase`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      p_user: uid,
      p_original_transaction_id: String(tx.originalTransactionId ?? ""),
      p_product_id: String(tx.productId ?? ""),
      p_tx: tx,
    }),
  });
  return new Response(await rpc.text(), { status: rpc.status, headers: { "Content-Type": "application/json" } });
});
