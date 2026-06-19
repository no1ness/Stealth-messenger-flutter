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
  const hasInput = await p.evaluate(() => !!document.querySelector("input"));
  if (hasInput) {
    console.log("Input ready at", t, "s");
    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

// Method 1: beforeinput + value set + input
const r1 = await p.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return "no input";
  
  inp.value = "Method1_42";
  inp.dispatchEvent(new InputEvent('beforeinput', {
    inputType: 'insertText',
    data: 'Method1_42',
    bubbles: true,
    cancelable: true,
  }));
  inp.dispatchEvent(new InputEvent('input', {
    inputType: 'insertText',
    data: 'Method1_42',
    bubbles: true,
    cancelable: true,
  }));
  inp.dispatchEvent(new Event('change', { bubbles: true }));
  return "dispatched: beforeinput+input+change";
});
console.log("M1:", r1);

await new Promise(r => setTimeout(r, 2000));

// Check semantics tree for the text field
let semText = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  const textField = all.find(s => s.textContent === "");
  const button = all.find(s => s.textContent === "НАЧАТЬ");
  return {
    textFieldText: textField?.textContent,
    buttonDisabled: button?.getAttribute("aria-disabled"),
  };
});
console.log("After M1:", JSON.stringify(semText));

// Method 2: Use playwrigh keyboard API on input
const inputEl = p.getByRole("textbox").first();
await inputEl.focus();
await new Promise(r => setTimeout(r, 500));
await p.keyboard.type("Method2_99", { delay: 50 });
await new Promise(r => setTimeout(r, 1000));

semText = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  const textField = all.find(s => s.textContent === "");
  const button = all.find(s => s.textContent === "НАЧАТЬ");
  return {
    textFieldText: textField?.textContent,
    buttonDisabled: button?.getAttribute("aria-disabled"),
    inputValue: document.querySelector("input")?.value,
  };
});
console.log("After keyboard.type:", JSON.stringify(semText));

// Method 3: Use evaluate to focus flutter-view and dispatch native keyboard events
await p.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return;
  
  // Clear first
  inp.value = "";
  
  // Simulate each keypress - use inputType insertText with single char
  const text = "Method3_abc";
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
});

await new Promise(r => setTimeout(r, 2000));

semText = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  const textField = all.find(s => s.textContent === "");
  const button = all.find(s => s.textContent === "НАЧАТЬ");
  return {
    textFieldText: textField?.textContent,
    buttonDisabled: button?.getAttribute("aria-disabled"),
    inputValue: document.querySelector("input")?.value,
  };
});
console.log("After char-by-char:", JSON.stringify(semText));

await b.close();
