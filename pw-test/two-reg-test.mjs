import { chromium } from 'playwright';
import { readContactBundle } from './contact-bundle-helper.mjs';

const delay = ms => new Promise(r => setTimeout(r, ms));
const BASE = "http://127.0.0.1:58585";

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

async function registerUser(page, label) {
  console.log(`[${label}] goto...`);
  for (let t = 1; t <= 20; t++) {
    try { await page.goto(BASE, { waitUntil: "domcontentloaded", timeout: 15000 }); break; }
    catch(e) { console.log(`  goto retry ${t}`); await delay(2000); }
  }
  
  console.log(`[${label}] wait for a11y...`);
  for (let t = 1; t <= 40; t++) {
    await page.evaluate(() => {
      // Try both selectors
      const el = document.querySelector('[aria-label="Enable accessibility"]') || 
                 document.querySelector('flt-semantics-placeholder');
      if (el) el.click();
    });
    const hasInput = await page.evaluate(() => !!document.querySelector("input"));
    if (hasInput) { console.log(`  input ready at ${t}s`); break; }
    await delay(1000);
  }
  
  console.log(`[${label}] typing...`);
  await typeInto(page, label);

  const enabled = await page.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled();
  console.log(`  button enabled: ${enabled}`);
  if (!enabled) throw new Error("Button not enabled");

  await page.getByRole("button", { name: /НАЧАТЬ/i }).click();
  console.log(`[${label}] clicked, wait Chats...`);
  const chats = await page.getByRole("button", { name: /Chats/i })
    .waitFor({ state: "visible", timeout: 60000 })
    .then(() => true)
    .catch(e => { console.log(`  Chats error: ${e.message?.substring(0,80)}`); return false; });
  console.log(`  chats: ${chats}`);
  return chats;
}

const b = await chromium.launch({
  headless: true,
  args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"],
});

const ctx1 = await b.newContext({ permissions: ["microphone","camera"], viewport: { width:900, height:800 } });
const p1 = await ctx1.newPage();
const ctx2 = await b.newContext({ permissions: ["microphone","camera"], viewport: { width:900, height:800 } });
const p2 = await ctx2.newPage();

p1.on("console", m => { if(m.type()==="log") console.log("[P1]", m.text().substring(0,150)); });
p2.on("console", m => { if(m.type()==="log") console.log("[P2]", m.text().substring(0,150)); });

const suffix = Date.now().toString(36);

console.log("=== Register User1 ===");
const ok1 = await registerUser(p1, "User1_"+suffix);
console.log("User1 done:", ok1);

console.log("=== Register User2 ===");
const ok2 = await registerUser(p2, "User2_"+suffix);
console.log("User2 done:", ok2);

if (ok1 && ok2) {
  try {
    const b1 = await readContactBundle(p1);
    const b2 = await readContactBundle(p2);
    console.log("Bundle1:", b1?.substring(0,60));
    console.log("Bundle2:", b2?.substring(0,60));
  } catch(e) { console.log("Bundle error:", e.message?.substring(0,80)); }
}

await b.close();
