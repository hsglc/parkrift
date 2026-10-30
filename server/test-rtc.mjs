// End-to-end check of the fast (UDP-like) path: two fake players join a room, each gets a
// Cloudflare Realtime session through the room socket, and car states go both ways over the
// unordered, no-retransmit DataChannels. Needs `npm i werift` (a WebRTC stack for Node).
import { RTCPeerConnection } from "werift";

const base = process.env.ROOM_URL || "wss://parkrift.huseyinglc0-946.workers.dev";
const code = Array.from({ length: 4 }, () => String.fromCharCode(65 + Math.floor(Math.random() * 26))).join("");
const FAST = { ordered: false, maxRetransmits: 0, negotiated: true };

function open(path) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(base + path);
    const inbox = [];
    const waiters = [];
    ws.addEventListener("message", (event) => {
      const data = JSON.parse(event.data);
      const index = waiters.findIndex((w) => w.match(data));
      if (index >= 0) waiters.splice(index, 1)[0].resolve(data);
      else inbox.push(data);
    });
    ws.addEventListener("open", () => resolve({
      ws,
      send: (obj) => ws.send(JSON.stringify(obj)),
      next: (match, ms = 15000) => new Promise((res, rej) => {
        const found = inbox.findIndex(match);
        if (found >= 0) return res(inbox.splice(found, 1)[0]);
        const timer = setTimeout(() => rej(new Error("timeout waiting for message")), ms);
        waiters.push({ match, resolve: (d) => { clearTimeout(timer); res(d); } });
      }),
    }));
    ws.addEventListener("error", () => reject(new Error("socket error " + path)));
  });
}

const check = (cond, label) => {
  if (!cond) { console.error("FAIL:", label); process.exit(1); }
  console.log("ok:", label);
};

// One player: room socket, then its SFU session (offer from the SFU, our answer), then the
// published channel; returns once subscribed to the friend.
async function player(role) {
  const room = await open(`/room/${code}?role=${role}`);
  await room.next((d) => d.t === "welcome");
  return room;
}

async function fast(room, name) {
  const pc = new RTCPeerConnection({ iceServers: [{ urls: "stun:stun.cloudflare.com:3478" }], bundlePolicy: "max-bundle" });
  const started = Date.now();
  room.send({ t: "rtc" });
  const offer = await room.next((d) => d.t === "rtcoffer");
  check(offer.sdp.includes("m=application"), `${name}: SFU offer has a data section`);
  await pc.setRemoteDescription({ type: "offer", sdp: offer.sdp });
  await pc.setLocalDescription(await pc.createAnswer());
  room.send({ t: "rtcanswer", sdp: pc.localDescription.sdp });
  await room.next((d) => d.t === "rtcok");
  await new Promise((resolve, reject) => {
    if (pc.connectionState === "connected") return resolve();
    const timer = setTimeout(() => reject(new Error(name + " not connected: " + pc.connectionState)), 15000);
    pc.connectionStateChange.subscribe((state) => {
      if (state === "connected") { clearTimeout(timer); resolve(); }
    });
  });
  check(true, `${name}: connected to the SFU in ${Date.now() - started} ms`);
  room.send({ t: "rtcup" });
  const pub = await room.next((d) => d.t === "rtcpub");
  const out = pc.createDataChannel("s", { ...FAST, id: pub.id });
  return { pc, out };
}

const host = await player("host");
const guest = await player("guest");
const [h, g] = await Promise.all([fast(host, "host"), fast(guest, "guest")]);

// Subscriptions arrive once both have published
const [hs, gs] = await Promise.all([host.next((d) => d.t === "rtcsub"), guest.next((d) => d.t === "rtcsub")]);
const received = { host: [], guest: [] };
const hin = h.pc.createDataChannel("s-in", { ...FAST, id: hs.id });
const gin = g.pc.createDataChannel("s-in", { ...FAST, id: gs.id });
hin.onmessage = (e) => received.host.push(JSON.parse(e.data));
gin.onmessage = (e) => received.guest.push(JSON.parse(e.data));
const opened = (ch) => new Promise((resolve) => {
  if (ch.readyState === "open") return resolve();
  ch.stateChanged.subscribe((s) => { if (s === "open") resolve(); });
});
await Promise.all([opened(h.out), opened(g.out), opened(hin), opened(gin)]);
check(true, "all four channels open");

// 3 s of 30 Hz states both ways
const sentAt = new Map();
for (let i = 0; i < 90; i++) {
  const ts = Date.now();
  sentAt.set(i, ts);
  h.out.send(JSON.stringify({ t: "s", i, ts }));
  g.out.send(JSON.stringify({ t: "s", i, ts }));
  await new Promise((r) => setTimeout(r, 33));
}
await new Promise((r) => setTimeout(r, 1000));
console.log(`guest got ${received.guest.length}/90 from host, host got ${received.host.length}/90 from guest`);
check(received.guest.length >= 80 && received.host.length >= 80, "states arrive both ways over the fast path");

h.pc.close(); g.pc.close();
host.ws.close(); guest.ws.close();
process.exit(0);
