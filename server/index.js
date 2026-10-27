// ParkPark room relay: two players per room, identified by a 4-letter code.
// The server only routes messages; game logic runs on the phones.
import { DurableObject } from "cloudflare:workers";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return new Response("parkpark ok", { headers: { "content-type": "text/plain" } });
    }
    if (url.pathname === "/" || url.pathname === "/support") return page(SUPPORT);
    if (url.pathname === "/privacy") return page(PRIVACY);
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

function page(body) {
  const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>ParkPark</title>
<style>body{font:16px/1.55 -apple-system,system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px 18px;color:#1b1d24;background:#fafafa}
h1{font-size:28px;margin:0 0 4px}h2{font-size:19px;margin:28px 0 6px}a{color:#0a5bd8}.muted{color:#666;font-size:14px}
hr{border:0;border-top:1px solid #ddd;margin:32px 0}@media(prefers-color-scheme:dark){body{background:#111318;color:#e8e9ee}.muted{color:#9a9ca5}hr{border-color:#333}a{color:#6aa8ff}}</style>
</head><body>${body}</body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8" } });
}

const SUPPORT = `<h1>ParkPark</h1><p class="muted">Destek · Support</p>
<h2>Türkçe</h2>
<p>ParkPark; tek başına park bölümleri, şehirde araba ve park yarışları ve bir arkadaşınla oda koduyla online oynanan bir araba oyunudur.</p>
<p>Soru, hata bildirimi ya da öneri için e-posta gönder: <a href="mailto:${CONTACT}">${CONTACT}</a>. Genellikle birkaç gün içinde yanıt veriyoruz.</p>
<p><a href="/privacy">Gizlilik Politikası</a></p>
<h2>English</h2>
<p>ParkPark is a car game with solo parking levels, city car and parking races, and online play with a friend using a room code.</p>
<p>For questions, bug reports or ideas, email <a href="mailto:${CONTACT}">${CONTACT}</a>. We usually reply within a few days.</p>
<p><a href="/privacy">Privacy Policy</a></p>`;

const PRIVACY = `<h1>Gizlilik Politikası · Privacy Policy</h1><p class="muted">ParkPark · Son güncelleme / Last updated: 27 Ekim / October 2026</p>
<h2>Türkçe</h2>
<p><b>Kişisel veri toplamıyoruz.</b> ParkPark'ta hesap, kayıt, reklam, analitik ya da takip yoktur. Konum, kişiler, kamera, mikrofon gibi izinler istenmez.</p>
<p><b>Cihazda saklananlar:</b> Bölüm yıldızların, en iyi sürelerin, seçtiğin araba ve boya ile ses ayarı yalnızca telefonunda saklanır. Uygulamayı silince bunlar da silinir.</p>
<p><b>Online oyun:</b> Bir oda kurduğunda ya da bir odaya katıldığında, oyun 4 harfli oda kodunu ve oyun sırasındaki araba konumu, hız, korna ve seçilen araba gibi oyun mesajlarını, arkadaşının cihazına iletmek için sunucumuz üzerinden gönderir. Sunucu (Cloudflare Workers) bu mesajları yalnızca iletir; saklamaz ve kimseyle paylaşmaz. Bağlantı sırasında barındırma sağlayıcısı, hizmeti çalıştırmak için IP adresi gibi teknik bilgileri kısa süreli işleyebilir.</p>
<p><b>Çocuklar:</b> Uygulama bilerek çocuklardan kişisel veri toplamaz.</p>
<p><b>Silme ve onay:</b> Online oyunu kullanmazsan hiçbir veri gönderilmez. Cihazdaki verileri uygulamayı silerek kaldırabilirsin. Soruların için: <a href="mailto:${CONTACT}">${CONTACT}</a></p>
<p><b>Değişiklikler:</b> Bu politika değişirse bu sayfa güncellenir.</p>
<h2>English</h2>
<p><b>We do not collect personal data.</b> ParkPark has no accounts, sign-up, ads, analytics or tracking. It does not ask for location, contacts, camera or microphone access.</p>
<p><b>Stored on your device:</b> your level stars, best times, chosen car and paint, and sound setting are kept only on your phone. Deleting the app deletes them.</p>
<p><b>Online play:</b> when you create or join a room, the game sends the 4-letter room code and game messages (car position, speed, horn, chosen car) through our server so they reach your friend's device. The server (Cloudflare Workers) only relays these messages; it does not store or share them. While connected, the hosting provider may briefly process technical information such as your IP address to run the service.</p>
<p><b>Children:</b> the app does not knowingly collect personal data from children.</p>
<p><b>Deletion and consent:</b> if you do not use online play, nothing is sent. You can remove the on-device data by deleting the app. Questions: <a href="mailto:${CONTACT}">${CONTACT}</a></p>
<p><b>Changes:</b> if this policy changes, this page will be updated.</p>
<hr><p class="muted"><a href="/support">Destek / Support</a></p>`;

export class Room extends DurableObject {
  async fetch(request) {
    const url = new URL(request.url);
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

  webSocketMessage(ws, message) {
    if (typeof message !== "string" || message.length > 4096) return;
    let data;
    try { data = JSON.parse(message); } catch (e) { return; }
    if (data.t === "ping") {
      ws.send(JSON.stringify({ t: "pong" }));
      return;
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
