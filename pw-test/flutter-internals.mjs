import { chromium } from 'playwright';

const b = await chromium.launch({ headless: true, args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"] });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto("http://127.0.0.1:58585", { waitUntil: "domcontentloaded", timeout:15000 });

for (let t=1; t<=20; t++) {
  const r = await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility']");
    if (el) { el.click(); return "CLICKED"; }
    const inp = document.querySelector("input");
    if (inp) {
      const keys = Object.keys(window).filter(k => k.startsWith("flutter") || k.startsWith("_"));
      return "INPUT_FOUND window.keys=" + JSON.stringify(keys);
    }
    return "WAIT";
  });
  if (r !== "WAIT") { console.log("T="+t+"s:", r); break; }
  await new Promise(r => setTimeout(r, 1000));
}

const r2 = await p.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return "no input";
  const flutterKeys = Object.getOwnPropertyNames(window).filter(k => /flutter|text|input|_f/i.test(k));
  return {
    flutterKeys,
    inputProps: {
      id: inp.id,
      className: inp.className,
      role: inp.getAttribute("role"),
      semanticsRole: inp.getAttribute("data-semantics-role"),
      ariaLabel: inp.getAttribute("aria-label"),
      value: inp.value,
      parentTag: inp.parentElement?.tagName,
      grandparentTag: inp.parentElement?.parentElement?.tagName,
    }
  };
});
console.log("Flutter internals:", JSON.stringify(r2, null, 2));

// Try various input events to trigger Flutter
const r3 = await p.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return "no input";

  // Method 1: InputEvent with insertText
  inp.value = "Alice_via_direct";
  inp.dispatchEvent(new InputEvent('input', {
    inputType: 'insertText',
    data: 'Alice_via_direct',
    bubbles: true,
    cancelable: true,
    composed: true,
  }));
  inp.dispatchEvent(new Event('change', { bubbles: true }));
  
  return {
    valueAfterInputEvent: inp.value,
  };
});
console.log("After InputEvent:", JSON.stringify(r3, null, 2));

await new Promise(r => setTimeout(r, 2000));

// Check if button is enabled
const r4 = await p.evaluate(() => {
  const buttons = document.querySelectorAll("button");
  const btnInfo = Array.from(buttons).slice(0, 5).map(b => ({
    label: b.getAttribute("aria-label"),
    role: b.getAttribute("data-semantics-role"),
    text: b.textContent?.substring(0, 30),
    disabled: b.hasAttribute("disabled") || b.getAttribute("aria-disabled"),
  }));
  return btnInfo;
});
console.log("Buttons:", JSON.stringify(r4, null, 2));

// Also check using Playwright
const btnEnabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled().catch(() => "err");
console.log("Button enabled (Playwright):", btnEnabled);

await b.close();
