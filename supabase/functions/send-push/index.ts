const env = (k: string): string => Deno.env.get(k) ?? "";

const b64url = (data: ArrayBuffer | Uint8Array | string): string => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

const pemBody = (pem: string): Uint8Array =>
  Uint8Array.from(atob(pem.replace(/\\n/g, "\n").replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));

let cached: { jwt: string; at: number } | null = null;

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 40 * 60) return cached.jwt;
  const key = await crypto.subtle.importKey("pkcs8", pemBody(env("APNS_KEY_P8")), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = b64url(JSON.stringify({ alg: "ES256", kid: env("APNS_KEY_ID") }));
  const claims = b64url(JSON.stringify({ iss: env("APNS_TEAM_ID"), iat: now }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${claims}`));
  cached = { jwt: `${head}.${claims}.${b64url(sig)}`, at: now };
  return cached.jwt;
}

type Row = { id: number; user_id: string; category: string; title: string; body: string };
type Device = { token: string; environment: string; categories: string[] };

const rest = (path: string, init: RequestInit = {}): Promise<Response> =>
  fetch(`${env("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
      Authorization: `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });

async function push(device: Device, row: Row): Promise<number> {
  const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": env("APNS_BUNDLE_ID"),
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify({ aps: { alert: { title: row.title, body: row.body }, sound: "default" }, category: row.category }),
  });
  await res.body?.cancel();
  return res.status;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  if (req.headers.get("Authorization") !== `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`) return new Response("Forbidden", { status: 403 });
  if (!env("APNS_KEY_P8") || !env("APNS_KEY_ID") || !env("APNS_TEAM_ID") || !env("APNS_BUNDLE_ID")) return new Response("APNs secrets missing", { status: 500 });

  const pending: Row[] = await (await rest("push_outbox?sent_at=is.null&order=id.asc&limit=100")).json();
  let sent = 0;
  for (const row of pending) {
    const devices: Device[] = await (await rest(`device_tokens?user_id=eq.${row.user_id}&select=token,environment,categories`)).json();
    for (const d of devices) {
      if (!d.categories.includes(row.category)) continue;
      const status = await push(d, row);
      if (status === 200) sent++;
      if (status === 410) await rest(`device_tokens?token=eq.${d.token}`, { method: "DELETE" });
    }
    await rest(`push_outbox?id=eq.${row.id}`, { method: "PATCH", body: JSON.stringify({ sent_at: new Date().toISOString() }) });
  }
  return Response.json({ rows: pending.length, sent });
});
