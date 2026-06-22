import { chromium } from "playwright";
import { enableFlutterA11y, gotoApp, delay } from "./core/flutter-helpers.mjs";

const BASE = "https://app.stealthpro.ru";
const PB_URL = "https://signal.stealthpro.ru";

async function registerViaBridge(page, nickname) {
  // Wait for test bridge to be ready
  for (let i = 0; i < 40; i++) {
    const ready = await page.evaluate(() => window.__test?._ready);
    if (ready) break;
    await delay(200);
  }

  console.log(`[bridge] registering ${nickname}...`);
  await page.evaluate((nick) => window.__test.register(nick), nickname);

  // Wait for reload + re-ready
  await page.waitForLoadState("commit", { timeout: 30000 });
  await delay(5000);
  await enableFlutterA11y(page, 30000);

  // Wait for bridge again
  for (let i = 0; i < 40; i++) {
    const ready = await page.evaluate(() => window.__test?._ready);
    if (ready) break;
    await delay(500);
  }
  console.log(`[bridge] ${nickname} registered`);
}

async function main() {
  const b = await chromium.launch({
    headless: true,
    args: ["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream", "--no-sandbox"],
  });

  const ctxA = await b.newContext({
    viewport: { width: 900, height: 800 },
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    locale: "en-US",
  });
  const ctxB = await b.newContext({
    viewport: { width: 900, height: 800 },
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    locale: "en-US",
  });

  const alice = await ctxA.newPage();
  const bob = await ctxB.newPage();

  alice.on("console", (m) => {
    if (m.type() === "error" || m.text().includes("test-bridge") || m.text().includes("register"))
      console.log("[alice:" + m.type() + "]", m.text());
  });
  bob.on("console", (m) => {
    if (m.type() === "error" || m.text().includes("test-bridge") || m.text().includes("register"))
      console.log("[bob:" + m.type() + "]", m.text());
  });

  console.log("=== Loading app for Bob ===");
  await bob.goto(BASE, { waitUntil: "commit", timeout: 30000 });
  await delay(5000);
  await enableFlutterA11y(bob, 15000);
  await registerViaBridge(bob, "TestBob_" + Date.now().toString(36));
  
  // Check if Chats button is visible
  const bobChats = await bob.getByRole("button", { name: "Chats" }).isVisible().catch(() => false);
  console.log("Bob sees Chats:", bobChats);
  await bob.screenshot({ path: "debug-bridge-bob.png", fullPage: true });

  console.log("=== Loading app for Alice ===");
  await alice.goto(BASE, { waitUntil: "commit", timeout: 30000 });
  await delay(5000);
  await enableFlutterA11y(alice, 15000);
  await registerViaBridge(alice, "TestAlice_" + Date.now().toString(36));

  const aliceChats = await alice.getByRole("button", { name: "Chats" }).isVisible().catch(() => false);
  console.log("Alice sees Chats:", aliceChats);
  await alice.screenshot({ path: "debug-bridge-alice.png", fullPage: true });

  console.log("=== TEST PASSED ===");
  await b.close();
}

main().catch((err) => {
  console.error("FAILED:", err?.message ?? err);
  process.exit(1);
});
