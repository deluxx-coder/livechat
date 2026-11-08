// Vercel Serverless Function: /api/chat
// Storage: Upstash Redis (Vercel Marketplace -> Storage -> Upstash Redis)
// Env: KV_REST_API_URL, KV_REST_API_TOKEN (atau UPSTASH_REDIS_REST_URL / _TOKEN)
// Opsional:
//   CHAT_KEY        -> kalau diisi, client wajib kirim header x-chat-key yang sama
//   OWNER_USERNAMES -> daftar @username owner, pisah koma (default: wooda_stackerzzz)
//   OWNER_KEY       -> kalau diisi, role Owner HANYA diberikan kalau request membawa header
//                      x-owner-key yang sama (mencegah orang lain menyamar jadi owner)

const URL_ = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
const ROOMS = ["global"];
const KEEP = 100;
const MAX_LEN = 200;
const OWNERS = (process.env.OWNER_USERNAMES || "wooda_stackerzzz")
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

async function redis(commands) {
  const r = await fetch(`${URL_}/pipeline`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify(commands),
  });
  if (!r.ok) throw new Error("redis " + r.status);
  return (await r.json()).map((x) => x.result);
}

const clean = (s, max) =>
  String(s ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);

// "wooda_stackerzzz" -> "wooda******" (depan tetap, belakang jadi bintang)
function maskName(name) {
  const chars = Array.from(String(name || ""));
  const n = chars.length;
  if (n <= 1) return chars.join("");
  const keep = Math.min(5, Math.max(1, Math.floor(n / 3)));
  const stars = Math.min(6, Math.max(3, n - keep));
  return chars.slice(0, keep).join("") + "*".repeat(stars);
}

// client mengirim "DisplayName|username"
function parseUser(raw) {
  const s = clean(raw, 45); // display (maks 20) + "|" + username (maks 20)
  const i = s.lastIndexOf("|");
  if (i > 0) return { disp: s.slice(0, i).trim(), uname: s.slice(i + 1).trim() };
  return { disp: s, uname: s };
}

// Bentuk pesan yang dikirim ke client: username asli TIDAK pernah keluar dari server.
function toPublic(m) {
  if (m.u !== undefined) {
    return { id: m.id, name: m.d, handle: m.u, role: m.r, text: m.text, t: m.t, user: `${m.d}|${m.u}` };
  }
  // pesan lama (format lama: { id, user, text, t })
  const { disp, uname } = parseUser(m.user);
  const handle = maskName(uname);
  const name = !disp || disp.toLowerCase() === uname.toLowerCase() ? handle : disp;
  const role = OWNERS.includes(uname.toLowerCase()) ? "Owner" : "Member";
  return { id: m.id, name, handle, role, text: m.text, t: m.t, user: `${name}|${handle}` };
}

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type,x-chat-key,x-owner-key");
  if (req.method === "OPTIONS") return res.status(200).end();

  if (process.env.CHAT_KEY && req.headers["x-chat-key"] !== process.env.CHAT_KEY) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const room = String((req.method === "GET" ? req.query.room : req.body?.room) || "global");
  if (!ROOMS.includes(room)) return res.status(400).json({ error: "bad room" });
  const key = `chat:${room}`;

  try {
    if (req.method === "GET") {
      const since = parseInt(req.query.since) || 0;
      const [raw] = await redis([["LRANGE", key, 0, KEEP - 1]]);
      const messages = (raw || [])
        .map((s) => { try { return JSON.parse(s); } catch { return null; } })
        .filter((m) => m && m.id > since)
        .sort((a, b) => a.id - b.id)
        .map(toPublic);
      return res.status(200).json({ messages });
    }

    if (req.method === "POST") {
      const { disp, uname } = parseUser(req.body?.user);
      const text = clean(req.body?.text, MAX_LEN);
      if (!uname || !/^[A-Za-z0-9_]{1,20}$/.test(uname) || !text) {
        return res.status(400).json({ error: "empty" });
      }
      const uid = clean(req.body?.uid, 20).replace(/\D/g, "") || uname;

      const [ok] = await redis([["SET", `rl:${room}:${uid}`, 1, "NX", "PX", 1500]]);
      if (ok !== "OK") return res.status(429).json({ error: "slow down" });

      // role dihitung di server
      const claimsOwner = OWNERS.includes(uname.toLowerCase());
      const ownerKeyOk = !process.env.OWNER_KEY || req.headers["x-owner-key"] === process.env.OWNER_KEY;
      const role = claimsOwner && ownerKeyOk ? "Owner" : "Member";

      // sensor di server sebelum disimpan
      const handle = maskName(uname);
      const name = !disp || disp.toLowerCase() === uname.toLowerCase() ? handle : clean(disp, 20);

      const [id] = await redis([["INCR", `${key}:id`]]);
      // uid disimpan (untuk moderasi) tapi tidak pernah dikirim balik ke client
      const msg = JSON.stringify({ id, d: name, u: handle, r: role, uid, text, t: Date.now() });
      await redis([["LPUSH", key, msg], ["LTRIM", key, 0, KEEP - 1]]);
      return res.status(200).json({ ok: true, id });
    }

    return res.status(405).json({ error: "method" });
  } catch (e) {
    return res.status(500).json({ error: "server" });
  }
};
