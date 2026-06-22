import { chromium } from "playwright";
import { enableFlutterA11y, delay } from "./core/flutter-helpers.mjs";

const b = await chromium.launch({ headless: true, args: ["--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream","--no-sandbox"] });
const ctx = await b.newContext({ viewport: { width: 900, height: 800 }, permissions: ["microphone","camera","clipboard-read","clipboard-write"], locale: "en-US" });
const page = await ctx.newPage();
page.on("console", m => {
  const txt = m.text();
  if (m.type() === "error" || txt.includes("register") || txt.includes("auth") || txt.includes("error"))
    console.log("[" + m.type() + "]", txt);
});

await page.goto("https://app.stealthpro.ru", { waitUntil: "commit", timeout: 30000 });
await delay(5000);
await enableFlutterA11y(page, 15000);

const textbox = page.getByRole("textbox").first();
await textbox.click();
await delay(300);

// Method: focus input then use execCommand insertText
const result = await page.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return "NO INPUT";
  inp.focus();
  const ok = document.execCommand("insertText", false, "TestAlice");
  return { execCommand: ok, value: inp.value };
});
console.log("execCommand result:", JSON.stringify(result));
await delay(500);

await page.screenshot({ path: "debug-execcommand.png", fullPage: true });

// Check if НАЧАТЬ is enabled now
const startBtn = page.getByRole("button", { name: /НАЧАТЬ|GET STARTED/i });
const isEnabled = await startBtn.isEnabled();
console.log("НАЧАТЬ enabled:", isEnabled);

if (isEnabled) {
  await startBtn.click({ force: true, noWaitAfter: true });
  console.log("Clicked НАЧАТЬ");
  for (let i = 0; i < 20; i++) {
    await delay(2000);
    const btns = await page.getByRole("button").allTextContents();
    if (btns.some(b => b === "Chats")) { console.log("SUCCESS: Chats visible!"); break; }
    if (i === 19) console.log("TIMEOUT:", btns);
  }
}

await page.screenshot({ path: "debug-execcommand-result.png", fullPage: true });
await b.close();
