import { chromium } from 'playwright';

const b = await chromium.launch({ headless: true, args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"] });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto("http://127.0.0.1:58585", { waitUntil: "domcontentloaded", timeout:15000 });

for (let t = 1; t <= 20; t++) {
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  const hasInput = await p.evaluate(() => document.querySelector('input[aria-label="Введите ваш алиас..."]') !== null);
  if (hasInput) {
    console.log("Input ready at", t, "s");
    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

// Type using evaluate char-by-char with beforeinput+input
const text = "AliceTest_42";
await p.evaluate((text) => {
  const inp = document.querySelector('input[aria-label="Введите ваш алиас..."]');
  if (!inp) return;
  
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    inp.value = inp.value + char;
    inp.dispatchEvent(new InputEvent('beforeinput', {
      inputType: 'insertText',
      data: char,
      bubbles: true,
    }));
    inp.dispatchEvent(new InputEvent('input', {
      inputType: 'insertText',
      data: char,
      bubbles: true,
    }));
  }
  inp.dispatchEvent(new Event('change', { bubbles: true }));
}, text);

await new Promise(r => setTimeout(r, 3000));

// Check Playwright accessibility state
const btnCount = await p.getByRole("button", { name: /НАЧАТЬ/i }).count();
console.log("Button count (НАЧАТЬ):", btnCount);

if (btnCount > 0) {
  const isDisabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isDisabled();
  const isEnabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled();
  console.log("Button disabled:", isDisabled, "enabled:", isEnabled);
  
  // Try clicking
  if (isEnabled) {
    console.log("Clicking НАЧАТЬ...");
    await p.getByRole("button", { name: /НАЧАТЬ/i }).click();
    await new Promise(r => setTimeout(r, 5000));
    
    // Check if we navigated to main screen
    const chatsTab = await p.getByRole("button", { name: /Chats/i }).count();
    console.log("Chats tab found:", chatsTab > 0);
  }
}

const finalSem = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  return all.slice(-5).map(s => ({
    text: s.textContent?.substring(0, 60),
    role: s.getAttribute("data-semantics-role"),
    disabled: s.getAttribute("aria-disabled"),
  }));
});
console.log("Final semantics:", JSON.stringify(finalSem, null, 2));

// Also check localStorage
const ls = await p.evaluate(() => {
  const keys = Object.keys(localStorage);
  const vals = {};
  for (const k of keys) {
    try { vals[k] = JSON.parse(localStorage[k]).substring(0, 40); } catch { vals[k] = localStorage[k].substring(0, 40); }
  }
  return vals;
});
console.log("localStorage:", JSON.stringify(ls, null, 2));

await b.close();
