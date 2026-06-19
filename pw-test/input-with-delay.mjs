import { chromium } from 'playwright';

import { WEB_URL, LAUNCH_ARGS } from './config.mjs';

const b = await chromium.launch({ headless: true, args: LAUNCH_ARGS });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto(WEB_URL, { waitUntil: "domcontentloaded", timeout:15000 });

for (let t = 1; t <= 20; t++) {
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  const hasInput = await p.evaluate(() => document.querySelector('input') !== null);
  if (hasInput) { console.log("Ready at", t, "s"); break; }
  await new Promise(r => setTimeout(r, 1000));
}

// Method A: char-by-char with delay between each via evaluate
console.log("Method A: char-by-char with delay...");
await p.evaluate(async (text) => {
  const inp = document.querySelector('input');
  if (!inp) return;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    inp.value = inp.value + char;
    inp.dispatchEvent(new InputEvent('beforeinput', {
      inputType: 'insertText', data: char, bubbles: true,
    }));
    inp.dispatchEvent(new InputEvent('input', {
      inputType: 'insertText', data: char, bubbles: true,
    }));
    await new Promise(r => setTimeout(r, 100));
  }
  inp.dispatchEvent(new Event('change', { bubbles: true }));
}, "AliceDelay_42");

await new Promise(r => setTimeout(r, 3000));

// Check state
const r1 = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  const button = all.find(s => s.textContent === "НАЧАТЬ");
  const textField = all.find(s => s.textContent === "");
  return {
    buttonDisabled: button?.getAttribute("aria-disabled"),
    textField: textField?.textContent,
    inputValue: document.querySelector("input")?.value,
  };
});
console.log("After A:", JSON.stringify(r1));

const btnEnabledPlaywright = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled().catch(() => "err");
console.log("Playwright button enabled:", btnEnabledPlaywright);

// Try clicking if enabled
if (btnEnabledPlaywright === true) {
  await p.getByRole("button", { name: /НАЧАТЬ/i }).click();
  await new Promise(r => setTimeout(r, 5000));
  
  const chatsTab = await p.getByRole("button", { name: /Chats/i }).count();
  console.log("On main screen (Chats tab visible):", chatsTab > 0);
}

await b.close();
