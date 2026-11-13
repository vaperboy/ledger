// Verifies an App Store signed JWS (StoreKit 2 transaction or server notification) with WebCrypto only:
// the x5c chain must end in Apple Root CA - G3 (pinned by SHA-256), each certificate must be signed by the next,
// valid on the signing date, and carry Apple's receipt-signing marks; then the JWS signature is checked with the leaf key.

export const APPLE_ROOT_CA_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

// 1.2.840.113635.100.6.11.1 (leaf) and 1.2.840.113635.100.6.2.1 (intermediate), DER encoded.
const LEAF_MARK = [0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01];
const INTERMEDIATE_MARK = [0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01];
const P256 = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07];
const P384 = [0x2b, 0x81, 0x04, 0x00, 0x22];
const ECDSA_SHA256 = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02];
const ECDSA_SHA384 = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03];

export class AppleJWSError extends Error {}

type TLV = { tag: number; at: number; start: number; end: number; next: number };

function tlv(b: Uint8Array, at: number): TLV {
  if (at + 2 > b.length) throw new AppleJWSError("der");
  const tag = b[at];
  let len = b[at + 1];
  let head = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 4 || at + 2 + n > b.length) throw new AppleJWSError("der");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + b[at + 2 + i];
    head = 2 + n;
  }
  const start = at + head;
  const end = start + len;
  if (end > b.length) throw new AppleJWSError("der");
  return { tag, at, start, end, next: end };
}

function children(b: Uint8Array, parent: TLV): TLV[] {
  const out: TLV[] = [];
  let at = parent.start;
  while (at < parent.end) {
    const t = tlv(b, at);
    out.push(t);
    at = t.next;
  }
  return out;
}

const same = (b: Uint8Array, t: TLV, ref: number[]): boolean =>
  t.end - t.start === ref.length && ref.every((v, i) => b[t.start + i] === v);

function contains(b: Uint8Array, ref: number[]): boolean {
  outer: for (let i = 0; i + ref.length <= b.length; i++) {
    for (let j = 0; j < ref.length; j++) if (b[i + j] !== ref[j]) continue outer;
    return true;
  }
  return false;
}

function time(b: Uint8Array, t: TLV): number {
  const s = new TextDecoder().decode(b.subarray(t.start, t.end));
  const full = t.tag === 0x18 ? s : (Number(s.slice(0, 2)) >= 50 ? "19" : "20") + s;
  const m = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(full);
  if (!m) throw new AppleJWSError("time");
  return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
}

type Cert = { der: Uint8Array; tbs: Uint8Array; sigHash: string; sig: Uint8Array; spki: Uint8Array; curve: string; notBefore: number; notAfter: number };

function parseCert(der: Uint8Array): Cert {
  const top = tlv(der, 0);
  const [tbsT, algT, sigT] = children(der, top);
  if (!tbsT || !algT || !sigT || sigT.tag !== 0x03) throw new AppleJWSError("cert");
  const algOid = children(der, algT)[0];
  const sigHash = same(der, algOid, ECDSA_SHA256) ? "SHA-256" : same(der, algOid, ECDSA_SHA384) ? "SHA-384" : "";
  if (!sigHash) throw new AppleJWSError("alg");
  const fields = children(der, tbsT);
  const i = fields[0].tag === 0xa0 ? 1 : 0;
  const validity = children(der, fields[i + 3]);
  const spkiT = fields[i + 5];
  const spkiAlg = children(der, children(der, spkiT)[0]);
  const curve = spkiAlg[1] && same(der, spkiAlg[1], P256) ? "P-256" : spkiAlg[1] && same(der, spkiAlg[1], P384) ? "P-384" : "";
  if (!curve) throw new AppleJWSError("curve");
  return {
    der,
    tbs: der.slice(tbsT.at, tbsT.end),
    sigHash,
    sig: der.slice(sigT.start + 1, sigT.end),
    spki: der.slice(spkiT.at, spkiT.end),
    curve,
    notBefore: time(der, validity[0]),
    notAfter: time(der, validity[1]),
  };
}

// ECDSA signatures in certificates are DER (r, s); WebCrypto wants r and s as fixed-size halves.
function rawSignature(sig: Uint8Array, size: number): Uint8Array {
  const seq = tlv(sig, 0);
  const [r, s] = children(sig, seq);
  const out = new Uint8Array(size * 2);
  for (const [k, part] of [r, s].entries()) {
    let v = sig.subarray(part.start, part.end);
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) throw new AppleJWSError("sig");
    out.set(v, k * size + (size - v.length));
  }
  return out;
}

function b64(s: string): Uint8Array {
  const std = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(std + "===".slice((std.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

const hex = (buf: ArrayBuffer): string => Array.from(new Uint8Array(buf), (x) => x.toString(16).padStart(2, "0")).join("");

async function key(cert: Cert): Promise<CryptoKey> {
  return await crypto.subtle.importKey("spki", cert.spki, { name: "ECDSA", namedCurve: cert.curve }, false, ["verify"]);
}

export async function verifyAppleJWS(jws: string, opts: { rootSha256?: string; now?: number } = {}): Promise<Record<string, unknown>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppleJWSError("format");
  const header = JSON.parse(new TextDecoder().decode(b64(parts[0])));
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length < 3) throw new AppleJWSError("header");
  const payload = JSON.parse(new TextDecoder().decode(b64(parts[1])));
  const certs = (header.x5c as string[]).map((c) => parseCert(b64(c)));
  const root = certs[certs.length - 1];
  const pin = (opts.rootSha256 ?? APPLE_ROOT_CA_G3_SHA256).toLowerCase().replace(/[^0-9a-f]/g, "");
  if (hex(await crypto.subtle.digest("SHA-256", root.der)) !== pin) throw new AppleJWSError("root");
  if (!contains(certs[0].der, LEAF_MARK) || !contains(certs[1].der, INTERMEDIATE_MARK)) throw new AppleJWSError("marks");
  const at = typeof payload.signedDate === "number" ? payload.signedDate : (opts.now ?? Date.now());
  for (const c of certs) if (at < c.notBefore || at > c.notAfter) throw new AppleJWSError("expired");
  for (let i = 0; i < certs.length - 1; i++) {
    const issuer = certs[i + 1];
    const size = issuer.curve === "P-384" ? 48 : 32;
    const ok = await crypto.subtle.verify({ name: "ECDSA", hash: certs[i].sigHash }, await key(issuer), rawSignature(certs[i].sig, size), certs[i].tbs);
    if (!ok) throw new AppleJWSError("chain");
  }
  const leaf = certs[0];
  if (leaf.curve !== "P-256") throw new AppleJWSError("leaf");
  const signed = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, await key(leaf), b64(parts[2]), signed);
  if (!ok) throw new AppleJWSError("signature");
  return payload;
}
