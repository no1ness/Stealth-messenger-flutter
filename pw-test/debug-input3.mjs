import { chromium } from "playwright";
import { enableFlutterA11y, delay } from "./core/flutter-helpers.mjs";

const b = await chromium.launch({ headless: true, args: ["--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream","--no-sandbox"] });
const ctx = await b.newContext({ viewport: { width: 900, height: 800 }, permissions: ["microphone","camera","clipboard-read","clipboard-write"], locale: "en-US" });
const page = await ctx.newPage();
page.on("console", m => {
  const txt = m.text();
  if (m.type() === "error" || txt.includes("register") || txt.includes("auth") || txt.includes("nickname"))
    console.log("[" + m.type() + "]", txt);
});

await page.goto("https://app.stealthpro.ru", { waitUntil: "commit", timeout: 30000 });
await delay(5000);
await enableFlutterA11y(page, 15000);

// Click the textbox via a11y to focus Flutter's internal text field
const textbox = page.getByRole("textbox").first();
await textbox.click();
await delay(300);

// Now type character by character via keyboard with delay - this sends real key events
// that Flutter's canvas handler captures
await page.keyboard.type("TestAlice", { delay: 100 });
await delay(1000);

// Check if the button is enabled now
const startBtn = page.getByRole("button", { name: /НАЧАТЬ|GET STARTED/i });
const isEnabled = await startBtn.isEnabled();
console.log("НАЧАТЬ enabled after keyboard.type:", isEnabled);

await page.screenshot({ path: "debug-kbdelay.png", fullPage: true });

if (!isEnabled) {
  // Try alternative: use arrow keys / backspace to trigger Flutter's input processing
  console.log("Trying alternative: focus input element directly and use CDP...");
  
  // Use CDP to send real keyboard input
  const client = await ctx.newCDPSession(page);
  
  // Focus the textbox
  await textbox.click();
  await delay(200);
  
  // Use Input.dispatchKeyEvent via CDP
  const text = "TestAlice2";
  for (const ch of text) {
    await client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      text: ch,
      key: ch,
      code: "Key" + ch.toUpperCase(),
      windowsVirtualKeyCode: ch.charCodeAt(0),
      nativeVirtualKeyCode: ch.charCodeAt(0),
    });
    await client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: ch,
      code: "Key" + ch.toUpperCase(),
      windowsVirtualKeyCode: ch.charCodeAt(0),
      nativeVirtualKeyCode: ch.charCodeAt(0),
    });
    await delay(50);
  }
  await delay(1000);

  const isEnabled2 = await startBtn.isEnabled();
  console.log("НАЧАТЬ enabled after CDP:", isEnabled2);
  
  await page.screenshot({ path: "debug-cdp.png", fullPage: true });
}

// If still not enabled, try clipboard paste approach
if (!(await startBtn.isEnabled())) {
  console.log("Trying clipboard paste...");
  await textbox.click();
  await delay(200);
  
  // Write to clipboard and paste
  await page.evaluate(() => {
    navigator.clipboard.writeText("TestAlice3");
  });
  await delay(100);
  await page.keyboard.press("Control+v");
  await delay(1000);
  
  const isEnabled3 = await startBtn.isEnabled();
  console.log("НАЧАТЬ enabled after paste:", isEnabled3);
  await page.screenshot({ path: "debug-paste.png", fullPage: true });
}

await b.close();
