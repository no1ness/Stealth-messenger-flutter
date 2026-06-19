import { chromium } from 'playwright';
import { WEB_URL } from './config.mjs';

const delay = ms => new Promise(r => setTimeout(r, ms));
const BASE = WEB_URL;

async function typeInto(page, text) {
  const f = page.getByRole("textbox").first();
  await f.focus();
  await delay(300);
  await page.keyboard.press("ArrowRight");
  await delay(200);
  await page.evaluate((txt) => {
    const inp = document.querySelector("input");
    if (!inp) return;
    inp.value = "";
    for (let i = 0; i < txt.length; i++) {
      const ch = txt[i];
      inp.value += ch;
      inp.dispatchEvent(new InputEvent("beforeinput", { inputType: "insertText", data: ch, bubbles: true }));
      inp.dispatchEvent(new InputEvent("input", { inputType: "insertText", data: ch, bubbles: true }));
    }
    inp.dispatchEvent(new Event("change", { bubbles: true }));
  }, text);
  await delay(500);
}

const b = await chromium.launch({
  headless: true,
  args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"],
});
const ctx = await b.newContext({ permissions: ["microphone","camera","clipboard-read","clipboard-write"], viewport: { width:900, height:800 } });
const p = await ctx.newPage();

p.on("pageerror", err => console.log(">> PAGE ERROR:", err.message?.slice(0,150)));
p.on("crash", () => console.log(">> PAGE CRASHED <<"));

for (let t = 1; t <= 20; t++) {
  try { await p.goto(BASE, { waitUntil: "domcontentloaded", timeout: 15000 }); break; }
  catch(e) { await delay(2000); }
}

for (let t = 1; t <= 30; t++) {
  await p.evaluate(() => {
    const el = document.querySelector('[aria-label="Enable accessibility"]') || document.querySelector('flt-semantics-placeholder');
    if (el) el.click();
  });
  if (await p.evaluate(() => !!document.querySelector("input"))) break;
  await delay(1000);
}

console.log("A11y enabled, registering...");
await typeInto(p, "DebugUser");
await p.getByRole("button", { name: /НАЧАТЬ/i }).click();
await p.getByRole("button", { name: /Chats/i }).waitFor({ state: "visible", timeout: 60000 });
console.log("Registered");

// Read bundle
const bundle = await p.evaluate(async () => {
  for (let i = 0; i < 40; i++) {
    if (window.stealthCrypto) break;
    await new Promise(r => setTimeout(r, 300));
  }
  async function readValue(key) {
    const raw = localStorage.getItem(`flutter.${key}`) || localStorage.getItem(key);
    if (!raw) return null;
    let enc;
    try { enc = JSON.parse(raw); } catch (_) { enc = raw; }
    try { return await window.stealthCrypto.decrypt(enc); } catch (_) { return null; }
  }
  const userId = await readValue("userId");
  const nickname = await readValue("nickname");
  const publicKey = await readValue("publicKey");
  if (!userId || !publicKey) return null;
  const payload = JSON.stringify({ v:1, user_id:userId, name:nickname||userId, public_key:publicKey });
  const utf8 = new TextEncoder().encode(payload);
  let bin = "";
  utf8.forEach(b => bin += String.fromCharCode(b));
  return `stealth:${btoa(bin).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,"")}`;
});
console.log("Bundle:", bundle?.slice(0,60));

// Go to Contacts, Add contact
await p.getByRole("button", { name: /Contacts/i }).click();
await delay(1000);
await p.getByRole("button", { name: /Add contact/i }).last().click();
await delay(1000);

// Paste bundle
await p.evaluate((id) => {
  const ta = document.createElement("textarea");
  ta.value = id;
  document.body.appendChild(ta);
  ta.select();
  document.execCommand("copy");
  document.body.removeChild(ta);
}, bundle);

// Wait for search field and paste
const searchField = p.getByRole("textbox").first();
await searchField.waitFor({ state: "visible", timeout: 10000 }).catch(() => {});
// Try pasting - the Flutter "Paste contact" reads from clipboard
await p.getByRole("button", { name: /Вставить контакт/i }).click().catch(() => {});
await delay(5000);

// Examine canvas and semantics node
const layout = await p.evaluate(() => {
  const canvas = document.querySelector("canvas.flt-canvas, canvas");
  const semBtn = document.querySelector('[aria-label*="Save contact"]');
  return {
    canvas: canvas ? {
      tag: canvas.tagName,
      w: canvas.offsetWidth,
      h: canvas.offsetHeight,
      rect: canvas.getBoundingClientRect(),
      style: canvas.style.cssText,
      pointerEvents: getComputedStyle(canvas).pointerEvents,
      zIndex: getComputedStyle(canvas).zIndex,
    } : null,
    semBtn: semBtn ? {
      tag: semBtn.tagName,
      w: semBtn.offsetWidth,
      h: semBtn.offsetHeight,
      rect: semBtn.getBoundingClientRect(),
      style: semBtn.style.cssText,
      pointerEvents: getComputedStyle(semBtn).pointerEvents,
      zIndex: getComputedStyle(semBtn).zIndex,
      posLeft: semBtn.style.left,
      posTop: semBtn.style.top,
      dataset: Object.fromEntries(Object.entries(semBtn.dataset || {}).map(([k,v]) => [k, v?.slice?.(0,80)])),
    } : null,
  };
});
console.log("Layout:", JSON.stringify(layout, null, 2));

// Now try mouse.click at button position and check events
const btnBox = layout.semBtn?.rect;
if (btnBox) {
  const cx = btnBox.x + btnBox.width/2;
  const cy = btnBox.y + btnBox.height/2;
  
  // Listen for console events to see if Flutter logs anything
  console.log(`Clicking at (${cx}, ${cy})...`);
  
  // Try multiple click strategies
  // 1. mouse.click
  await p.mouse.click(cx, cy);
  await delay(2000);
  
  const afterClick = await p.evaluate(() => ({
    stillHasInput: !!document.querySelector('[aria-label="Contact bundle input"]'),
    semCount: document.querySelectorAll('[aria-label*="Save contact"]').length,
    errMsg: window._lastFlutterError?.slice(0, 200),
  }));
  console.log("After mouse.click:", JSON.stringify(afterClick));
  
  // 2. locator.click (might crash, that's OK for debug)
  if (afterClick.stillHasInput) {
    console.log("Trying Playwright locator.click...");
    try {
      await p.locator('[aria-label*="Save contact"]').click({ timeout: 5000 });
      await delay(2000);
      const afterLocator = await p.evaluate(() => ({
        stillHasInput: !!document.querySelector('[aria-label="Contact bundle input"]'),
      })).catch(e => ({ error: e.message?.slice(0,60) }));
      console.log("After locator.click:", JSON.stringify(afterLocator));
    } catch (e) {
      console.log("locator.click error:", e.message?.slice(0,80));
      // Check if page is still alive
      try {
        const alive = await p.evaluate(() => "alive");
        console.log("Page still alive:", alive);
      } catch (e2) {
        console.log("Page not alive:", e2.message?.slice(0,60));
      }
    }
  }
}

await b.close();
