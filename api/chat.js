// Vercel Serverless Function: /api/chat
// Storage: Upstash Redis (Vercel Marketplace -> Storage -> Upstash Redis)
// Env: KV_REST_API_URL, KV_REST_API_TOKEN (atau UPSTASH_REDIS_REST_URL / _TOKEN)
// Opsional: CHAT_KEY -> kalau diisi, client wajib kirim header x-chat-key yang sama

const URL_ = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
const ROOMS = ["global"];
const KEEP = 100;
const MAX_LEN = 200;

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

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Access-Control-Allow-Origin", "*");
res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
res.setHeader("Access-Control-Allow-Headers", "Content-Type,x-chat-key");
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
        .sort((a, b) => a.id - b.id);
      return res.status(200).json({ messages });
    }

    if (req.method === "POST") {
      const user = clean(req.body?.user, 20);
      const uid = clean(req.body?.uid, 20) || user;
      const text = clean(req.body?.text, MAX_LEN);
      if (!user || !text) return res.status(400).json({ error: "empty" });

      const [ok] = await redis([["SET", `rl:${room}:${uid}`, 1, "NX", "PX", 1500]]);
      if (ok !== "OK") return res.status(429).json({ error: "slow down" });

      const [id] = await redis([["INCR", `${key}:id`]]);
      const msg = JSON.stringify({ id, user, text, t: Date.now() });
      await redis([["LPUSH", key, msg], ["LTRIM", key, 0, KEEP - 1]]);
      return res.status(200).json({ ok: true, id });
    }

    return res.status(405).json({ error: "method" });
  } catch (e) {
    return res.status(500).json({ error: "server" });
  }
};
