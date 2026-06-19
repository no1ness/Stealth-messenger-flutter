import { createReadStream, existsSync, statSync } from "fs";
import { createServer } from "http";
import { extname, join, normalize, resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { WEB_URL } from "./config.mjs";

const _dirname = dirname(fileURLToPath(import.meta.url));

const HOST = process.env.STEALTH_WEB_HOST || "127.0.0.1";
const PORT = Number(process.env.STEALTH_WEB_PORT || WEB_URL.split(":").pop().replace("/", ""));
const ROOT = resolve(_dirname, "..", "client", "build", "web");

const MIME_TYPES = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".wasm": "application/wasm",
};

function resolvePath(urlPath) {
  const sanitized = normalize(decodeURIComponent(urlPath).replace(/^\/+/, ""));
  const candidate = resolve(ROOT, sanitized);
  if (!candidate.startsWith(ROOT)) {
    return null;
  }

  if (existsSync(candidate) && statSync(candidate).isFile()) {
    return candidate;
  }

  const fallback = join(ROOT, "index.html");
  return existsSync(fallback) ? fallback : null;
}

const server = createServer((req, res) => {
  const filePath = resolvePath(req.url || "/");
  if (!filePath) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
    return;
  }

  const mimeType = MIME_TYPES[extname(filePath).toLowerCase()] || "application/octet-stream";
  res.writeHead(200, { "Content-Type": mimeType });
  createReadStream(filePath).pipe(res);
});

server.listen(PORT, HOST, () => {
  console.log(`Static Flutter web server listening on http://${HOST}:${PORT}`);
  console.log(`Serving: ${ROOT}`);
});
