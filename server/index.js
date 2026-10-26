// ParkPark room relay: two players per room, identified by a 4-letter code.
// The server only routes messages; game logic runs on the phones.
import { DurableObject } from "cloudflare:workers";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === "/health") {
      return new Response("parkpark ok", { headers: { "content-type": "text/plain" } });
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
