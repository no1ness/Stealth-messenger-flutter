import { chromium } from 'playwright';

const b = await chromium.launch({ headless: true, args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"] });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto("http://127.0.0.1:58585", { waitUntil: "domcontentloaded", timeout:15000 });

// Wait for input
for (let t = 1; t <= 20; t++) {
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  const hasInput = await p.evaluate(() => document.querySelector("input")?.value !== undefined);
  if (hasInput) {
    console.log("Input ready at", t, "s");
    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

// Check the semantics node for the input and button
const semDetails = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  return all.map((s, i) => ({
    idx: i,
    role: s.getAttribute("data-semantics-role"),
    label: s.getAttribute("aria-label"),
    text: s.textContent?.substring(0, 80),
    disabled: s.hasAttribute("aria-disabled"),
    inherited: s.getAttribute("aria-disabled"),
  }));
});
console.log("Semantics details:", JSON.stringify(semDetails, null, 2));

// Check flutterCanvasKit API
const ck = await p.evaluate(() => {
  const ck = window.flutterCanvasKit;
  if (!ck) return "no canvaskit";
  const methods = Object.getOwnPropertyNames(ck).filter(k => typeof ck[k] === 'function').slice(0, 20);
  const props = Object.getOwnPropertyNames(ck).filter(k => typeof ck[k] !== 'function').slice(0, 20);
  return { methods, props };
});
console.log("flutterCanvasKit:", JSON.stringify(ck, null, 2));

// Check _flutter
const fl = await p.evaluate(() => {
  const f = window._flutter;
  if (!f) return "no _flutter";
  const methods = Object.keys(f);
  return { keys: methods };
});
console.log("_flutter:", JSON.stringify(fl, null, 2));

// Try to dispatch input via the flutter engine's internal path
// Set value using native setter then dispatch multiple types of events
const testResult = await p.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return "no input";
  
  const results = {};
  
  // Method 1: Just set value + input event (no InputEvent constructor)
  inp.value = "";
  inp.value = "Method1_test";
  const ev1 = new Event('input', { bubbles: true, cancelable: true });
  inp.dispatchEvent(ev1);
  results.method1 = { value: inp.value };
  
  // Wait a bit
  return new Promise(resolve => {
    setTimeout(() => {
      const finalValue = inp.value;
      inp.value = "Method1_final";
      const evFinal = new InputEvent('input', {
        inputType: 'insertText',
        data: 'Method1_final',
        bubbles: true,
        cancelable: true,
      });
      inp.dispatchEvent(evFinal);
      inp.dispatchEvent(new Event('change', { bubbles: true }));
      
      // Check if value was consumed (Flutter might clear it)
      setTimeout(() => {
        resolve({ finalValue, valueAfterFinal: inp.value });
      }, 1000);
    }, 2000);
  });
});
console.log("Test result:", JSON.stringify(testResult, null, 2));

// Check semantics again
const semAfter = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  return all.map((s, i) => ({
    idx: i,
    role: s.getAttribute("data-semantics-role"),
    text: s.textContent?.substring(0, 80),
    disabled: s.hasAttribute("aria-disabled"),
  }));
});
console.log("Semantics after:", JSON.stringify(semAfter, null, 2));

// Check if button is now enabled via Playwright accessibility tree
const btnCount = await p.getByRole("button", { name: /НАЧАТЬ/i }).count();
console.log("Button count (НАЧАТЬ):", btnCount);

if (btnCount > 0) {
  const isDisabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isDisabled();
  const isEnabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled();
  console.log("Button disabled:", isDisabled, "enabled:", isEnabled);
}

await b.close();
