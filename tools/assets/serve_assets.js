// Serveur local TEMPORAIRE : écoute uniquement sur 127.0.0.1, sert uniquement les fichiers listés, s'arrête seul.
const http = require("http");
const fs = require("fs");
const path = require("path");

const dir = process.argv[2];
const port = Number(process.argv[3]);
const lifetimeSeconds = Number(process.argv[4] || 300);
const allowed = new Set(fs.readdirSync(dir).filter((f) => f.toLowerCase().endsWith(".png")));

const server = http.createServer((req, res) => {
  const name = decodeURIComponent((req.url || "").split("?")[0].replace(/^\//, ""));
  console.log(new Date().toISOString(), req.method, req.url, "from", req.socket.remoteAddress);
  if (!allowed.has(name)) {
    res.writeHead(404);
    return res.end("not found");
  }
  const data = fs.readFileSync(path.join(dir, name));
  res.writeHead(200, { "Content-Type": "image/png", "Content-Length": data.length });
  res.end(data);
});

server.listen(port, "127.0.0.1", () => console.log("listening on 127.0.0.1:" + port, [...allowed].join(",")));
setTimeout(() => {
  console.log("arret automatique");
  process.exit(0);
}, lifetimeSeconds * 1000);
