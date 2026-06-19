import { chromium } from 'playwright';

import { WEB_URL, LAUNCH_ARGS } from './config.mjs';

const b = await chromium.launch({ headless: true, args: LAUNCH_ARGS });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto(WEB_URL, { waitUntil: "domcontentloaded", timeout:15000 });
console.log("DOM loaded");

// Wait for a11y toggle, click it, then wait for input
for (let t = 1; t <= 30; t++) {
  // Try clicking toggle
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  
  const hasInput = await p.evaluate(() => !!document.querySelector("input"));
  if (hasInput) {
    console.log("Input found at", t, "s");
    
    // Check all window properties related to flutter/text
    const info = await p.evaluate(() => {
      const w = window;
      const keys = [];
      for (const k in w) {
        if (k.startsWith("_") || k.toLowerCase().includes("flutter") || k.toLowerCase().includes("text")) {
          keys.push(k);
        }
      }
      // Look for dart or flutter specific
      const dartKeys = Object.keys(w).filter(k => k.startsWith("dart") || k.startsWith("$dart"));
      const inp = document.querySelector("input");
      const inpInfo = inp ? {
        id: inp.id,
        className: inp.className,
        value: inp.value,
        listeners: typeof getEventListeners !== 'undefined' ? getEventListeners(inp) : 'N/A',
      } : null;
      
      // Check main.dart.js exports
      const mainModule = document.querySelector('script[src*="main.dart"]')?.src;
      
      return { keys: keys.slice(0, 50), dartKeys, inpInfo, mainModule };
    });
    console.log("Info:", JSON.stringify(info, null, 2));
    
    // Check if there's a semantcis host
    const semInfo = await p.evaluate(() => {
      const host = document.querySelector("flt-semantics-host");
      if (!host) return { host: "not found" };
      const children = Array.from(host.querySelectorAll("flt-semantics")).slice(0, 10).map(s => ({
        role: s.getAttribute("data-semantics-role"),
        label: s.getAttribute("aria-label"),
        text: s.textContent?.substring(0, 50),
        tag: s.tagName,
      }));
      return { host: host.tagName, children };
    });
    console.log("Semantics:", JSON.stringify(semInfo, null, 2));
    
    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

// Now try typing with various methods
const inp = p.getByRole("textbox").first();
await inp.waitFor({ state: "visible", timeout: 10000 });
console.log("Textbox visible");

// Method: dispatch InputEvent on the semantics input via evaluate
await p.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return;
  
  // Set value and dispatch proper events
  inp.value = "TestAlias_42";
  inp.dispatchEvent(new InputEvent('input', {
    inputType: 'insertText',
    data: 'TestAlias_42',
    bubbles: true,
    cancelable: true,
  }));
  inp.dispatchEvent(new Event('change', { bubbles: true }));
});
console.log("Dispatched InputEvent");

await new Promise(r => setTimeout(r, 3000));

// Check button state
const btnState = await p.evaluate(() => {
  const btns = document.querySelectorAll("button");
  return Array.from(btns).slice(0, 5).map(b => ({
    label: b.getAttribute("aria-label"),
    role: b.getAttribute("data-semantics-role"),
    text: b.textContent?.substring(0, 30),
    disabled: b.hasAttribute("disabled"),
  }));
});
console.log("Buttons:", JSON.stringify(btnState, null, 2));

// Try keyboard typing on the Flutter view element
await p.evaluate(() => {
  const view = document.querySelector("flutter-view");
  if (view) {
    view.focus();
    view.dispatchEvent(new KeyboardEvent('keydown', { key: 'A', code: 'KeyA', bubbles: true }));
    view.dispatchEvent(new KeyboardEvent('keypress', { key: 'A', code: 'KeyA', charCode: 65, bubbles: true }));
    view.dispatchEvent(new KeyboardEvent('keyup', { key: 'A', code: 'KeyA', bubbles: true }));
  }
});
console.log("Sent key events to flutter-view");

await new Promise(r => setTimeout(r, 3000));

const btnState2 = await p.evaluate(() => {
  const btns = document.querySelectorAll("button");
  return Array.from(btns).slice(0, 5).map(b => ({
    label: b.getAttribute("aria-label"),
    role: b.getAttribute("data-semantics-role"),
    disabled: b.hasAttribute("disabled"),
  }));
});
console.log("After key events:", JSON.stringify(btnState2, null, 2));

const val = await p.evaluate(() => {
  const inp = document.querySelector("input");
  return inp ? inp.value : "no input";
});
console.log("Input value:", JSON.stringify(val));

await b.close();
