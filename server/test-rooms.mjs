// End-to-end check of the room server with two fake players (Node 22+ has a global WebSocket).
const base = process.env.ROOM_URL || "wss://parkrift.huseyinglc0-946.workers.dev";
const code = Array.from({ length: 4 }, () => String.fromCharCode(65 + Math.floor(Math.random() * 26))).join("");

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
      next: (match, ms = 5000) => new Promise((res, rej) => {
        const found = inbox.findIndex(match);
        if (found >= 0) return res(inbox.splice(found, 1)[0]);
        const timer = setTimeout(() => rej(new Error("timeout waiting for message")), ms);
        waiters.push({ match, resolve: (d) => { clearTimeout(timer); res(d); } });
      }),
    }));
    ws.addEventListener("error", (e) => reject(new Error("socket error " + path)));
  });
}

const check = (cond, label) => {
  if (!cond) { console.error("FAIL:", label); process.exit(1); }
  console.log("ok:", label);
};

const host = await open(`/room/${code}?role=host`);
const welcomeHost = await host.next((d) => d.t === "welcome");
check(welcomeHost.slot === 0, "host gets slot 0");

const guest = await open(`/room/${code}?role=guest`);
const welcomeGuest = await guest.next((d) => d.t === "welcome");
check(welcomeGuest.slot === 1 && welcomeGuest.peers.includes(0), "guest gets slot 1 and sees host");
check((await host.next((d) => d.t === "join")).slot === 1, "host is told the guest joined");

host.send({ t: "s", x: 10, y: 20 });
const relayed = await guest.next((d) => d.t === "s");
check(relayed.from === 0 && relayed.x === 10, "state relayed host -> guest");

guest.send({ t: "p", level: 1 });
check((await host.next((d) => d.t === "p")).from === 1, "event relayed guest -> host");

host.send({ t: "ping" });
check((await host.next((d) => d.t === "pong")).t === "pong", "ping/pong");

const third = await open(`/room/${code}?role=guest`);
check((await third.next((d) => d.t === "full")).t === "full", "third player is rejected (full)");

const lost = await open(`/room/ZZZZ?role=guest`);
check((await lost.next((d) => d.t === "noroom")).t === "noroom", "guest with unknown code gets noroom");

guest.ws.close();
check((await host.next((d) => d.t === "leave")).slot === 1, "host is told the guest left");

host.ws.close();
console.log("ALL ROOM CHECKS PASSED");
process.exit(0);
