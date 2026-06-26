import { createReadStream, existsSync, statSync } from "fs";
import { createServer } from "http";
import { extname, join, normalize, resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { WEB_URL } from "./config.mjs";

const _dirname = dirname(fileURLToPath(import.meta.url));

const HOST = process.env.STEALTH_WEB_HOST || "127.0.0.1";
const PORT = Number(process.env.STEALTH_WEB_PORT || new URL(WEB_URL).port || "58585");
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
  if (candidate.startsWith(ROOT) && existsSync(candidate) && statSync(candidate).isFile()) {
    return candidate;
  }

  // Directory or not found → SPA fallback to Flutter's index.html
  const fallback = join(ROOT, "index.html");
  return existsSync(fallback) ? fallback : null;
}

const server = createServer((req, res) => {
  const filePath = resolvePath(req.url || "/");
  if (!filePath || !existsSync(filePath) || !statSync(filePath).isFile()) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
    return;
  }

  const mimeType = MIME_TYPES[extname(filePath).toLowerCase()] || "application/octet-stream";
  const isImmutable = filePath.includes("main.dart.js") || extname(filePath).toLowerCase() === ".wasm";
  const headers = { "Content-Type": mimeType };
  if (isImmutable) {
    headers["Cache-Control"] = "public, max-age=31536000, immutable";
  } else {
    headers["Cache-Control"] = "no-cache";
  }

  res.writeHead(200, headers);
  createReadStream(filePath).pipe(res);
});

server.listen(PORT, HOST, () => {
  console.log(`Static Flutter web server listening on http://${HOST}:${PORT}`);
  console.log(`Serving: ${ROOT}`);
});