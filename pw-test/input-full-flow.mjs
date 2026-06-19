import { chromium } from 'playwright';

const b = await chromium.launch({ headless: true, args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"] });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto("http://127.0.0.1:58585", { waitUntil: "domcontentloaded", timeout:15000 });

// Wait for app boot
for (let t = 1; t <= 20; t++) {
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  if (await p.evaluate(() => document.querySelector('input') !== null)) {
    console.log("Ready at", t, "s");
    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

// === REGISTRATION FLOW ===
const nickname = "Alice_42";

// Step 1: Focus the input
const input = p.getByRole("textbox").first();
await input.focus();
await new Promise(r => setTimeout(r, 300));

// Step 2: Send trusted key event to activate Flutter text input
await p.keyboard.press("ArrowRight");
await new Promise(r => setTimeout(r, 200));

// Step 3: Type via evaluate char-by-char
await p.evaluate((text) => {
  const inp = document.querySelector('input');
  if (!inp) return;
  inp.value = "";
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    inp.value = inp.value + char;
    inp.dispatchEvent(new InputEvent('beforeinput', {
      inputType: 'insertText', data: char, bubbles: true,
    }));
    inp.dispatchEvent(new InputEvent('input', {
      inputType: 'insertText', data: char, bubbles: true,
    }));
  }
  inp.dispatchEvent(new Event('change', { bubbles: true }));
}, nickname);

await new Promise(r => setTimeout(r, 1000));

// Step 4: Check button
const btnEnabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled();
console.log("Button enabled:", btnEnabled);

if (!btnEnabled) {
  console.log("Button still disabled, aborting");
  await b.close();
  process.exit(1);
}

// Step 5: Click НАЧАТЬ
console.log("Clicking НАЧАТЬ...");
await p.getByRole("button", { name: /НАЧАТЬ/i }).click();

// Step 6: Wait for main screen
console.log("Waiting for Chats tab...");
const found = await p.getByRole("button", { name: /Chats/i }).waitFor({ state: "visible", timeout: 60000 }).then(() => true).catch(() => false);
console.log("Chats tab found:", found);

if (found) {
  console.log("REGISTRATION SUCCESSFUL!");
  
  // Check localStorage for registration data
  const ls = await p.evaluate(() => {
    const keys = Object.keys(localStorage);
    const vals = {};
    for (const k of keys) {
      try { vals[k] = localStorage[k].substring(0, 50); } catch { vals[k] = "?"; }
    }
    return vals;
  });
  console.log("localStorage after registration:", JSON.stringify(ls, null, 2));
}

await b.close();
