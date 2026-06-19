import { spawn } from "child_process";
import { Client } from "./client.mjs";
import { WEB_URL } from "../config.mjs";

const STATIC_PORT = WEB_URL.split(":").pop().replace("/", "");

export async function runScenario(scenarioFn, { startServer = false } = {}) {
  let serverProc = null;
  if (startServer) {
    serverProc = await startStaticServer();
  }

  const clientA = new Client("Alice");
  const clientB = new Client("Bob");

  try {
    const t0 = Date.now();
    await Promise.all([clientA.launch(), clientB.launch()]);
    console.log(
      `[runner] browsers launched in ${Date.now() - t0}ms`,
    );

    const env = {
      alice: clientA,
      bob: clientB,
      url: WEB_URL,
    };

    await scenarioFn(env);
    console.log("[runner] scenario PASSED");
    return { passed: true, duration: Date.now() - t0 };
  } catch (err) {
    console.error("[runner] scenario FAILED:", err.message);
    return { passed: false, error: err.message };
  } finally {
    await clientA.close();
    await clientB.close();
    if (serverProc) {
      serverProc.kill();
    }
  }
}

function startStaticServer() {
  const proc = spawn("node", ["serve-static-web.mjs"], {
    cwd: new URL("../", import.meta.url).pathname,
    env: { ...process.env, STEALTH_WEB_PORT: STATIC_PORT },
    stdio: ["ignore", "pipe", "pipe"],
  });

  proc.stdout.on("data", (d) => process.stdout.write(`[web] ${d}`));
  proc.stderr.on("data", (d) => process.stderr.write(`[web] ${d}`));

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Static server start timeout")), 10000);
    proc.stdout.on("data", (data) => {
      const text = data.toString();
      if (text.includes("listening on")) {
        clearTimeout(timeout);
        resolve(proc);
      }
    });
    proc.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });
    proc.on("exit", (code) => {
      clearTimeout(timeout);
      if (code !== 0) reject(new Error(`Static server exited with code ${code}`));
    });
  });
}
