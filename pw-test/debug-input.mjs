import { chromium } from "playwright";
import { enableFlutterA11y, delay } from "./core/flutter-helpers.mjs";

const b = await chromium.launch({ headless: true, args: ["--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream","--no-sandbox"] });
const ctx = await b.newContext({ viewport: { width: 900, height: 800 }, permissions: ["microphone","camera"], locale: "en-US" });
const page = await ctx.newPage();

await page.goto("https://app.stealthpro.ru", { waitUntil: "commit", timeout: 30000 });
await delay(5000);
await enableFlutterA11y(page, 15000);

const editables = await page.evaluate(() => {
  const all = document.querySelectorAll('input, textarea, [contenteditable]');
  return Array.from(all).map(el => ({
    tag: el.tagName,
    type: el.type,
    value: el.value,
    className: el.className,
    parentTag: el.parentElement?.tagName,
  }));
});
console.log("Editable elements:", JSON.stringify(editables, null, 2));

const flutterInputs = await page.evaluate(() => {
  const gp = document.querySelector("flt-glass-pane");
  if (!gp) return "no glass-pane";
  const sr = gp.shadowRoot;
  if (!sr) return "no shadow";
  const inputs = sr.querySelectorAll("input, textarea");
  return Array.from(inputs).map(i => ({ tag: i.tagName, type: i.type, value: i.value }));
});
console.log("Flutter shadow inputs:", JSON.stringify(flutterInputs));

// Try clicking on the input area directly via coordinates
const textbox = page.getByRole("textbox").first();
const box = await textbox.boundingBox();
console.log("Textbox bounding box:", JSON.stringify(box));

// Try clicking the canvas area where the input should be and typing
if (box) {
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await delay(300);
  await page.keyboard.type("TestAlice", { delay: 50 });
  await delay(500);
  
  const val = await page.evaluate(() => {
    const inp = document.querySelector("input");
    return inp ? inp.value : "NO INPUT";
  });
  console.log("After mouse click + keyboard type, input value:", val);
}

await page.screenshot({ path: "debug-editables.png", fullPage: true });
await b.close();
