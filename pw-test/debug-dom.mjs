import { chromium } from 'playwright';
const delay = ms => new Promise(r => setTimeout(r, ms));

const b = await chromium.launch({
  headless: true,
  args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"],
});
const p = await (await b.newContext({ permissions: ["microphone","camera","clipboard-read","clipboard-write"], viewport: { width:900, height:800 } })).newPage();

for (let t = 1; t <= 20; t++) {
  try { await p.goto("http://127.0.0.1:58585", { waitUntil: "domcontentloaded", timeout: 15000 }); break; }
  catch(e) { await delay(2000); }
}

// Wait for app to load and a11y to be on
for (let t = 1; t <= 50; t++) {
  await p.evaluate(() => {
    const el = document.querySelector('[aria-label="Enable accessibility"], flt-semantics-placeholder');
    if (el) el.click();
  });
  if (await p.evaluate(() => !!document.querySelector("input"))) break;
  await delay(1000);
}

// Dump ALL top-level elements in body
const dom = await p.evaluate(() => {
  const all = document.body.querySelectorAll("*");
  const result = [];
  for (const el of all) {
    const tag = el.tagName.toLowerCase();
    if (!["flt-semantics", "span", "div", "input"].includes(tag)) {
      result.push({
        tag, id: el.id, className: el.className?.slice?.(0,40),
        rect: el.getBoundingClientRect(),
        style: { pos: el.style.position, pe: el.style.pointerEvents, z: el.style.zIndex },
        innerHTML: el.innerHTML?.slice?.(0,100),
      });
    }
  }
  // Also check for any shadow roots
  const shadowHosts = [];
  for (const el of all) {
    if (el.shadowRoot) {
      shadowHosts.push({ tag: el.tagName, id: el.id });
      // Check inside shadow root
      const shadowEls = el.shadowRoot.querySelectorAll("*");
      for (const se of shadowEls) {
        const st = se.tagName.toLowerCase();
        if (st === "canvas" || st === "div" || st.includes("flt")) {
          result.push({ tag: st + "(shadow)", id: se.id, className: se.className?.slice?.(0,40) });
        }
      }
    }
  }
  return { result, shadowHosts, bodyChildren: Array.from(document.body.children).map(c => c.tagName) };
});
console.log("DOM structure:", JSON.stringify(dom, null, 2));
await b.close();
