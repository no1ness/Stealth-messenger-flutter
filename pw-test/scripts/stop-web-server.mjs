import { execSync } from "child_process";
import { fileURLToPath } from "url";

export function stopWebServer() {
  try {
    execSync("pkill -f 'flutter.*web-server' 2>/dev/null || true", { stdio: "ignore" });
  } catch {
    // ignore
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  stopWebServer();
}
