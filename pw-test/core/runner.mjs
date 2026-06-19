import { spawn } from "child_process";
import { Client } from "./client.mjs";
import { WEB_URL, SCREENSHOT_ON_FAILURE } from "../config.mjs";

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
    console.log(`[runner] browsers launched in ${Date.now() - t0}ms`);

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
    await captureFailureScreenshots(clientA, clientB, "scenario");
    return { passed: false, error: err.message };
  } finally {
    await clientA.close();
    await clientB.close();
    if (serverProc) {
      serverProc.kill();
    }
  }
}

export async function runSuite(scenarios, { startServer = false } = {}) {
  let serverProc = null;
  if (startServer) {
    serverProc = await startStaticServer();
  }

  const browser = null; // Client will launch its own
  const alice = new Client("Alice");
  const bob = new Client("Bob");

  try {
    const t0 = Date.now();
    await Promise.all([alice.launch(), bob.launch()]);
    console.log(`[suite] browsers launched in ${Date.now() - t0}ms`);

    const suffix = Date.now().toString(36);
    await Promise.all([
      alice.register("SuiteAlice_" + suffix),
      bob.register("SuiteBob_" + suffix),
    ]);
    console.log(`[suite] users registered in ${Date.now() - t0}ms`);

    for (let i = 0; i < scenarios.length; i++) {
      const { name, fn } = scenarios[i];
      if (i > 0) {
        // Reset both users to main screen after previous scenario (e.g. call screen)
        await Promise.all([alice.resetToMain(), bob.resetToMain()]);
        console.log(`[suite] reset to main screen`);
      }
      const st = Date.now();
      try {
        await fn({ alice, bob, url: WEB_URL });
        console.log(`[suite] ${name}: PASS (${Date.now() - st}ms)`);
      } catch (err) {
        console.error(`[suite] ${name}: FAIL - ${err.message}`);
        await captureFailureScreenshots(alice, bob, name);
        return { passed: false, error: err.message, scenario: name };
      }
    }

    console.log(`[suite] all ${scenarios.length} scenarios PASSED in ${Date.now() - t0}ms`);
    return { passed: true, duration: Date.now() - t0 };
  } catch (err) {
    console.error("[suite] FAILED:", err.message);
    return { passed: false, error: err.message };
  } finally {
    await alice.close();
    await bob.close();
    if (serverProc) {
      serverProc.kill();
    }
  }
}

async function captureFailureScreenshots(alice, bob, label) {
  if (!SCREENSHOT_ON_FAILURE) return;
  const suffix = Date.now().toString(36);
  await alice.screenshot(`artifacts/${label}-alice-${suffix}.png`).catch(() => {});
  await bob.screenshot(`artifacts/${label}-bob-${suffix}.png`).catch(() => {});
  console.warn(`[runner] screenshots saved for ${label}`);
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
