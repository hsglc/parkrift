// Parkrift room relay: two players per room, identified by a 4-letter code.
// The server only routes messages; game logic runs on the phones.
import { DurableObject } from "cloudflare:workers";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return new Response("parkrift ok", { headers: { "content-type": "text/plain" } });
    }
    if (url.pathname === "/" || url.pathname === "/support") return page(SUPPORT);
    if (url.pathname === "/privacy") return page(PRIVACY);
    // Rövanş links: a run (the driver's nickname, time and ghost) kept 30 days under a code
    if (url.pathname === "/challenge" && request.method === "POST") return createChallenge(request, env);
    const challenge = url.pathname.match(/^\/(challenge|c)\/([A-Z2-9]{6})$/);
    if (challenge) {
      const stub = env.ROOMS.get(env.ROOMS.idFromName("c:" + challenge[2]));
      const stored = await stub.fetch("https://store/store");
      if (stored.status !== 200) {
        return challenge[1] === "c" ? page(CHALLENGE_GONE) : new Response("not found", { status: 404 });
      }
      const run = await stored.json();
      if (challenge[1] === "challenge") {
        return new Response(JSON.stringify(run), { headers: { "content-type": "application/json" } });
      }
      return challengePage(challenge[2], run);
    }
    const match = url.pathname.match(/^\/room\/([A-Z]{4})$/);
    if (!match) return new Response("not found", { status: 404 });
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const stub = env.ROOMS.get(env.ROOMS.idFromName(match[1]));
    return stub.fetch(request);
  },
};

const CONTACT = "huseyinglc0@gmail.com";

const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

async function createChallenge(request, env) {
  const text = await request.text();
  if (text.length > 160000) return new Response("too large", { status: 413 });
  let body;
  try { body = JSON.parse(text); } catch (e) { return new Response("bad json", { status: 400 }); }
  const name = String(body.name || "").trim().slice(0, 16);
  const title = String(body.title || "").trim().slice(0, 60);
  const level = Number(body.level), time = Number(body.time), score = Number(body.score);
  const hits = Number(body.hits || 0);
  const precision = body.precision == null ? null : Number(body.precision);
  const ghost = body.ghost;
  const ok = name.length > 0 && Number.isInteger(level) && level >= 0 && level < 1000
    && isFinite(time) && time > 1 && time < 3600 && isFinite(score) && Number.isInteger(hits) && hits >= 0 && hits < 1000
    && (precision === null || (Number.isInteger(precision) && precision >= 0 && precision <= 100))
    && Array.isArray(ghost) && ghost.length >= 6 && ghost.length % 3 === 0 && ghost.length <= 3 * 6000
    && ghost.every((v) => Number.isInteger(v) && Math.abs(v) < 1e7);
  if (!ok) return new Response("bad run", { status: 400 });
  // The recording is the run: a time that does not match its length (a sample every 0.1 s) is refused
  const recorded = ghost.length / 3 * 0.1;
  if (Math.abs(recorded - time) > 1.5) return new Response("time does not match the run", { status: 422 });
  const run = { name, title, level, time, score, hits, precision, ghost, at: Date.now() };
  for (let attempt = 0; attempt < 5; attempt++) {
    const bytes = crypto.getRandomValues(new Uint8Array(6));
    const code = [...bytes].map((b) => CODE_LETTERS[b % CODE_LETTERS.length]).join("");
    const stub = env.ROOMS.get(env.ROOMS.idFromName("c:" + code));
    const put = await stub.fetch("https://store/store", { method: "PUT", body: JSON.stringify(run) });
    if (put.status === 200) {
      return new Response(JSON.stringify({ code }), { headers: { "content-type": "application/json" } });
    }
  }
  return new Response("busy", { status: 503 });
}

function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function challengePage(code, run) {
  const name = escapeHTML(run.name), title = escapeHTML(run.title || "Parkrift");
  const time = run.time.toFixed(1);
  const head = `<meta property="og:title" content="${name}: ${title} · ${time} sn">
<meta property="og:description" content="Parkrift'te bu süreyi geçebilir misin? · Can you beat this time in Parkrift?">`;
  const body = `<div style="text-align:center;padding-top:40px">
<p class="muted">Parkrift · Rövanş</p>
<h1>${name}</h1>
<p style="font-size:18px">${title}</p>
<p style="font-size:44px;font-weight:800;margin:8px 0">${time} sn</p>
<p>Bu süreyi geçebilir misin? · Can you beat this time?</p>
<p style="margin-top:28px"><a href="parkrift://c/${code}" style="display:inline-block;background:#ffcc33;color:#111;font-weight:800;padding:14px 34px;border-radius:30px;text-decoration:none">Parkrift'te aç · Open in Parkrift</a></p>
<p class="muted" style="margin-top:22px">Kod · Code: ${code}</p></div>`;
  return page(body, head);
}

const CHALLENGE_GONE = `<div style="text-align:center;padding-top:40px"><h1>Parkrift</h1>
<p>Bu meydan okumanın süresi dolmuş. · This challenge has expired.</p></div>`;

function page(body, head = "") {
  const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Parkrift</title>${head}
<style>body{font:16px/1.55 -apple-system,system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px 18px;color:#1b1d24;background:#fafafa}
h1{font-size:28px;margin:0 0 4px}h2{font-size:19px;margin:28px 0 6px}a{color:#0a5bd8}.muted{color:#666;font-size:14px}
hr{border:0;border-top:1px solid #ddd;margin:32px 0}@media(prefers-color-scheme:dark){body{background:#111318;color:#e8e9ee}.muted{color:#9a9ca5}hr{border-color:#333}a{color:#6aa8ff}}</style>
</head><body>${body}</body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8" } });
}

const SUPPORT = `<h1>Parkrift</h1><p class="muted">Destek · Support</p>
<h2>Türkçe</h2>
<p>Parkrift; tek başına park bölümleri, şehirde araba ve park yarışları ve bir arkadaşınla oda koduyla online oynanan bir araba oyunudur.</p>
<p>Soru, hata bildirimi ya da öneri için e-posta gönder: <a href="mailto:${CONTACT}">${CONTACT}</a>. Genellikle birkaç gün içinde yanıt veriyoruz.</p>
<p><a href="/privacy">Gizlilik Politikası</a></p>
<h2>English</h2>
<p>Parkrift is a car game with solo parking levels, city car and parking races, and online play with a friend using a room code.</p>
<p>For questions, bug reports or ideas, email <a href="mailto:${CONTACT}">${CONTACT}</a>. We usually reply within a few days.</p>
<p><a href="/privacy">Privacy Policy</a></p>`;

const PRIVACY = `<h1>Gizlilik Politikası · Privacy Policy</h1><p class="muted">Parkrift · Son güncelleme / Last updated: 30 Ekim / October 2026</p>
<h2>Türkçe</h2>
<p><b>Kişisel veri toplamıyoruz.</b> Sunucuda yalnızca senin paylaşmayı seçtiğin Rövanş kayıtları 30 gün tutulur (aşağıda). Parkrift'ta hesap, kayıt, reklam, analitik ya da takip yoktur. Konum, kişiler, kamera, mikrofon gibi izinler istenmez.</p>
<p><b>Cihazda saklananlar:</b> Bölüm yıldızların, en iyi sürelerin, seçtiğin araba ve boya ile ses ayarı yalnızca telefonunda saklanır. Uygulamayı silince bunlar da silinir.</p>
<p><b>Online oyun:</b> Bir oda kurduğunda ya da bir odaya katıldığında, oyun 4 harfli oda kodunu ve oyun sırasındaki araba konumu, hız, korna ve seçilen araba gibi oyun mesajlarını, arkadaşının cihazına iletmek için sunucumuz üzerinden gönderir. Sunucu (Cloudflare Workers ve Cloudflare Realtime) bu mesajları yalnızca iletir; saklamaz ve kimseyle paylaşmaz. Bağlantı sırasında barındırma sağlayıcısı, hizmeti çalıştırmak için IP adresi gibi teknik bilgileri kısa süreli işleyebilir.</p>
<p><b>Game Center:</b> Sıralamalar için Apple'ın Game Center hizmeti kullanılır; skorların ve Game Center takma adın Apple tarafından, Apple'ın gizlilik politikasına göre işlenir. Biz bu bilgileri toplamayız.</p>
<p><b>Hızlı eşleşme:</b> Hızlı eşleşmede de yalnızca oyun mesajları (araba konumu, hız, seçilen araba) rakibinin cihazına iletilir. Sohbet ya da kullanıcı içeriği yoktur.</p>
<p><b>Rövanş linkleri:</b> Bir bölümü bitirip "Meydan oku" ile link paylaştığında, seçtiğin takma ad, bölüm, süre, çarpma sayısı ve arabanın o sürüşteki yolu (hayalet kaydı) sunucumuzda bir kodla saklanır; linki açan herkes bunları görebilir. Bu kayıtlar 30 gün sonra kendiliğinden silinir. Gerçek adını yazmak zorunda değilsin.</p>
<p><b>Çocuklar:</b> Uygulama bilerek çocuklardan kişisel veri toplamaz.</p>
<p><b>Silme ve onay:</b> Online oyunu kullanmazsan hiçbir veri gönderilmez. Cihazdaki verileri uygulamayı silerek kaldırabilirsin. Soruların için: <a href="mailto:${CONTACT}">${CONTACT}</a></p>
<p><b>Değişiklikler:</b> Bu politika değişirse bu sayfa güncellenir.</p>
<h2>English</h2>
<p><b>We do not collect personal data.</b> The server keeps only the challenge runs you choose to share, for 30 days (below). Parkrift has no accounts, sign-up, ads, analytics or tracking. It does not ask for location, contacts, camera or microphone access.</p>
<p><b>Stored on your device:</b> your level stars, best times, chosen car and paint, and sound setting are kept only on your phone. Deleting the app deletes them.</p>
<p><b>Online play:</b> when you create or join a room, the game sends the 4-letter room code and game messages (car position, speed, horn, chosen car) through our server so they reach your friend's device. The server (Cloudflare Workers and Cloudflare Realtime) only relays these messages; it does not store or share them. While connected, the hosting provider may briefly process technical information such as your IP address to run the service.</p>
<p><b>Game Center:</b> leaderboards use Apple's Game Center; your scores and Game Center nickname are handled by Apple under Apple's privacy policy. We do not collect them.</p>
<p><b>Challenge links:</b> when you finish a level and share a link with "Challenge", the nickname you choose, the level, your time, crash count and the path your car drove (the ghost recording) are stored on our server under a code; anyone with the link can see them. They are deleted automatically after 30 days. You do not need to use your real name.</p>
<p><b>Quick match:</b> quick match also sends only game messages (car position, speed, chosen car) to your opponent's device. There is no chat or user content.</p>
<p><b>Children:</b> the app does not knowingly collect personal data from children.</p>
<p><b>Deletion and consent:</b> if you do not use online play, nothing is sent. You can remove the on-device data by deleting the app. Questions: <a href="mailto:${CONTACT}">${CONTACT}</a></p>
<p><b>Changes:</b> if this policy changes, this page will be updated.</p>
<hr><p class="muted"><a href="/support">Destek / Support</a></p>`;

// Realtime SFU (Cloudflare Realtime): each phone gets a WebRTC session whose DataChannels carry the
// car state unordered and without retransmission (UDP-like). The room socket is the signalling
// path: the Room makes the SFU API calls with the app secret, so only players in a room can use it.
const RTC_API = "https://rtc.live.cloudflare.com/v1/apps/";
const FAST = { dataChannelName: "s", ordered: false, maxRetransmits: 0 };

async function sfu(env, path, method, body) {
  const response = await fetch(RTC_API + env.RTC_APP_ID + path, {
    method,
    headers: { Authorization: `Bearer ${env.RTC_APP_SECRET}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = {};
  try { data = await response.json(); } catch (e) {}
  if (!response.ok || data.errorCode) throw new Error(`${path} ${response.status} ${data.errorCode || ""}`);
  return data;
}

export class Room extends DurableObject {
  async alarm() {
    await this.ctx.storage.deleteAll();
  }

  constructor(ctx, env) {
    super(ctx, env);
    // Per-slot queues: SFU mutations on one session run one after another
    this.queues = new Map();
  }

  queue(slot, work) {
    const next = (this.queues.get(slot) || Promise.resolve()).then(work).catch((e) => {
      console.log("rtc", slot, String(e));
    });
    this.queues.set(slot, next);
    return next;
  }

  update(ws, change) {
    const state = { ...(ws.deserializeAttachment() || {}), ...change };
    ws.serializeAttachment(state);
    return state;
  }

  async rtc(ws, data) {
    const me = ws.deserializeAttachment() || {};
    if (!this.env.RTC_APP_ID || !this.env.RTC_APP_SECRET) return;
    if (data.t === "rtc") {
      // A new session and its DataChannel transport; the phone answers the SFU's offer
      await this.queue(me.slot, async () => {
        const session = await sfu(this.env, "/sessions/new", "POST");
        const sid = session.sessionId;
        this.update(ws, { sid, pub: false, subTo: null });
        const transport = await sfu(this.env, `/sessions/${sid}/datachannels/establish`, "POST", {
          dataChannel: { location: "remote", dataChannelName: "server-events" },
        });
        ws.send(JSON.stringify({ t: "rtcoffer", sdp: transport.sessionDescription.sdp }));
      });
    } else if (data.t === "rtcanswer" && typeof data.sdp === "string" && data.sdp.length < 20000) {
      await this.queue(me.slot, async () => {
        const sid = (ws.deserializeAttachment() || {}).sid;
        if (!sid) return;
        await sfu(this.env, `/sessions/${sid}/renegotiate`, "PUT", {
          sessionDescription: { type: "answer", sdp: data.sdp },
        });
        ws.send(JSON.stringify({ t: "rtcok" }));
      });
    } else if (data.t === "rtcup") {
      // The phone's connection to the SFU is up: publish its state channel, then link it with
      // the friend's both ways
      await this.queue(me.slot, async () => {
        const state = ws.deserializeAttachment() || {};
        if (!state.sid || state.pub) return;
        const made = await sfu(this.env, `/sessions/${state.sid}/datachannels/new`, "POST", {
          dataChannels: [{ location: "local", ...FAST }],
        });
        const channel = (made.dataChannels || [])[0] || {};
        if (channel.errorCode || typeof channel.id !== "number") throw new Error("publish " + channel.errorCode);
        this.update(ws, { pub: true });
        ws.send(JSON.stringify({ t: "rtcpub", id: channel.id }));
        this.link();
      });
    }
  }

  /// Subscribes every published phone to the other's published channel (once per session).
  link() {
    const sockets = this.ctx.getWebSockets();
    for (const ws of sockets) {
      for (const other of sockets) {
        if (other === ws) continue;
        const me = ws.deserializeAttachment() || {};
        const them = other.deserializeAttachment() || {};
        if (!me.pub || !them.pub || me.subTo === them.sid) continue;
        this.update(ws, { subTo: them.sid });
        this.queue(me.slot, async () => {
          const current = ws.deserializeAttachment() || {};
          if (current.subTo !== them.sid || !current.sid) return;
          const made = await sfu(this.env, `/sessions/${current.sid}/datachannels/new`, "POST", {
            dataChannels: [{ location: "remote", sessionId: them.sid, ...FAST }],
          });
          const channel = (made.dataChannels || [])[0] || {};
          if (channel.errorCode || typeof channel.id !== "number") {
            this.update(ws, { subTo: null });
            throw new Error("subscribe " + channel.errorCode);
          }
          ws.send(JSON.stringify({ t: "rtcsub", id: channel.id }));
        });
      }
    }
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/store") {
      // A Rövanş run kept under its code (this object is named after it), deleted after 30 days
      if (request.method === "PUT") {
        if (await this.ctx.storage.get("run")) return new Response("taken", { status: 409 });
        await this.ctx.storage.put("run", await request.text());
        await this.ctx.storage.setAlarm(Date.now() + 30 * 24 * 3600 * 1000);
        return new Response("ok");
      }
      const run = await this.ctx.storage.get("run");
      return run ? new Response(run, { headers: { "content-type": "application/json" } }) : new Response("none", { status: 404 });
    }
    const role = url.searchParams.get("role") === "guest" ? "guest" : "host";
    const sockets = this.ctx.getWebSockets();
    const used = new Set(sockets.map((ws) => (ws.deserializeAttachment() || {}).slot));
    const slot = [0, 1].find((s) => !used.has(s));

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    const reject = (reason) => {
      server.accept();
      server.send(JSON.stringify({ t: reason }));
      server.close(4000, reason);
      return new Response(null, { status: 101, webSocket: client });
    };

    if (slot === undefined) return reject("full");
    if (role === "guest" && sockets.length === 0) return reject("noroom");

    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ slot });
    const peers = [...used].filter((s) => s !== undefined);
    server.send(JSON.stringify({ t: "welcome", slot, peers }));
    for (const ws of sockets) {
      try { ws.send(JSON.stringify({ t: "join", slot })); } catch (e) {}
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    if (typeof message !== "string" || message.length > 24000) return;
    let data;
    try { data = JSON.parse(message); } catch (e) { return; }
    if (data.t === "ping") {
      ws.send(JSON.stringify({ t: "pong" }));
      return;
    }
    if (data.t === "rtc" || data.t === "rtcanswer" || data.t === "rtcup") {
      return this.rtc(ws, data);
    }
    const me = ws.deserializeAttachment() || {};
    data.from = me.slot;
    const out = JSON.stringify(data);
    for (const other of this.ctx.getWebSockets()) {
      if (other !== ws) {
        try { other.send(out); } catch (e) {}
      }
    }
  }

  webSocketClose(ws, code, reason) {
    this.leave(ws);
    try { ws.close(code, reason); } catch (e) {}
  }

  webSocketError(ws) {
    this.leave(ws);
  }

  leave(ws) {
    const me = ws.deserializeAttachment() || {};
    for (const other of this.ctx.getWebSockets()) {
      if (other !== ws) {
        try { other.send(JSON.stringify({ t: "leave", slot: me.slot })); } catch (e) {}
      }
    }
  }
}
