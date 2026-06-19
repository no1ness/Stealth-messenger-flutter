import { spawn } from "child_process";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { WEB_URL } from "../config.mjs";

const CLIENT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "client");
const PORT = process.env.STEALTH_WEB_PORT || "57575";

export async function startWebServer() {
  const proc = spawn("flutter", [
    "run",
    "-d", "web-server",
    "--web-port", PORT,
  ], {
    cwd: CLIENT_DIR,
    stdio: ["ignore", "pipe", "pipe"],
  });

  proc.stderr.on("data", (d) => process.stderr.write(`[web] ${d}`));

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Web server start timeout")), 60000);
    proc.stdout.on("data", (data) => {
      const text = data.toString();
      process.stdout.write(`[web] ${text}`);
      if (text.includes("DevTools") && text.includes("listening on")) {
        clearTimeout(timeout);
        resolve();
      }
    });
    proc.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });
    proc.on("exit", (code) => {
      clearTimeout(timeout);
      if (code !== 0) reject(new Error(`Web server exited with code ${code}`));
    });
  });

  return proc;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const proc = await startWebServer();
  process.on("SIGINT", () => proc.kill());
  process.on("SIGTERM", () => proc.kill());
}
