import { chromium } from 'playwright';
import { readContactBundle } from './contact-bundle-helper.mjs';
import { WEB_URL, LAUNCH_ARGS } from './config.mjs';

const delay = ms => new Promise(r => setTimeout(r, ms));

const BASE = WEB_URL;

async function typeIntoTextField(page, text) {
  const field = page.getByRole("textbox").first();
  await field.focus();
  await delay(300);
  await page.keyboard.press("ArrowRight");
  await delay(200);
  await page.evaluate((txt) => {
    const inp = document.querySelector("input");
    if (!inp) return;
    inp.value = "";
    for (let i = 0; i < txt.length; i++) {
      const ch = txt[i];
      inp.value = inp.value + ch;
      inp.dispatchEvent(new InputEvent("beforeinput", { inputType: "insertText", data: ch, bubbles: true }));
      inp.dispatchEvent(new InputEvent("input", { inputType: "insertText", data: ch, bubbles: true }));
    }
    inp.dispatchEvent(new Event("change", { bubbles: true }));
  }, text);
  await delay(500);
}

const b = await chromium.launch({ headless: true, args: LAUNCH_ARGS });
const ctx = await b.newContext({ permissions: ["microphone","camera","clipboard-read","clipboard-write"], viewport: { width: 900, height: 800 } });
const p = await ctx.newPage();
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,150)); });

for (let t = 1; t <= 20; t++) {
  try {
    await p.goto(BASE, { waitUntil: "domcontentloaded", timeout: 15000 });
    break;
  } catch(e) { console.log("goto retry", t); await delay(2000); }
}

for (let t = 1; t <= 40; t++) {
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  if (await p.evaluate(() => document.querySelector("input") !== null)) { console.log("Input ready at", t, "s"); break; }
  await delay(1000);
}

console.log("Typing...");
await typeIntoTextField(p, "TestUser_42");
await delay(1000);

const enabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled();
console.log("Button enabled:", enabled);

if (enabled) {
  await p.getByRole("button", { name: /НАЧАТЬ/i }).click();
  console.log("Waiting for Chats tab...");
  const found = await p.getByRole("button", { name: /Chats/i }).waitFor({ state: "visible", timeout: 120000 }).then(() => true).catch(() => false);
  console.log("Chats:", found);

  if (found) {
    const bundle = await readContactBundle(p);
    console.log("Contact bundle:", bundle);
  }
} else {
  console.log("Button NOT enabled - trying char-by-char with delay");
}

await delay(2000);
await b.close();
