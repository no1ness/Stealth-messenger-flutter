import { chromium } from 'playwright';
import crypto from 'crypto';
import { WEB_URL, LAUNCH_ARGS } from './config.mjs';

const b = await chromium.launch({ headless: true, args: LAUNCH_ARGS });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto(WEB_URL, { waitUntil: "domcontentloaded", timeout:15000 });

// Click a11y toggle and wait for app to boot
for (let t = 1; t <= 20; t++) {
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  const hasCrypto = await p.evaluate(() => window.stealthCrypto !== undefined);
  if (hasCrypto) {
    console.log("App booted at", t, "s");
    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

// Dump ALL localStorage keys
const ls = await p.evaluate(() => {
  const keys = Object.keys(localStorage);
  const vals = {};
  for (const k of keys) {
    try { vals[k] = JSON.parse(localStorage[k]); } catch { vals[k] = localStorage[k].substring(0, 100) + '...'; }
  }
  return vals;
});
console.log("localStorage:", JSON.stringify(ls, null, 2));

// Check stealthCrypto API
const cryptoAPI = await p.evaluate(() => {
  if (!window.stealthCrypto) return "not available";
  const methods = Object.getOwnPropertyNames(window.stealthCrypto).filter(k => typeof window.stealthCrypto[k] === 'function');
  const props = Object.getOwnPropertyNames(window.stealthCrypto).filter(k => typeof window.stealthCrypto[k] !== 'function');
  return { methods, props };
});
console.log("stealthCrypto:", JSON.stringify(cryptoAPI, null, 2));

await b.close();
