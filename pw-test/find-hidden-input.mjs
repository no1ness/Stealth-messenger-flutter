import { chromium } from 'playwright';

const b = await chromium.launch({ headless: true, args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"] });
const p = await b.newPage({ viewport: { width: 900, height: 800 } });
p.on("console", m => { if(m.type()==="log") console.log("[log]", m.text().substring(0,200)); });
await p.goto("http://127.0.0.1:58585", { waitUntil: "domcontentloaded", timeout:15000 });

// Wait for a11y toggle
for (let t = 1; t <= 20; t++) {
  await p.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) el.click();
  });
  const hasInput = await p.evaluate(() => {
    const count = document.querySelectorAll("input, textarea, [contenteditable]").length;
    return count > 0;
  });
  if (hasInput) {
    console.log("Found some inputs at", t, "s");
    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

// List ALL input/textarea elements with their styles/positions
const allInputs = await p.evaluate(() => {
  const all = document.querySelectorAll("input, textarea, [contenteditable], [role='textbox']");
  return Array.from(all).map((el, i) => {
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return {
      idx: i,
      tag: el.tagName,
      type: el.getAttribute("type"),
      role: el.getAttribute("role"),
      id: el.id,
      className: el.className,
      ariaLabel: el.getAttribute("aria-label"),
      ariaHidden: el.getAttribute("aria-hidden"),
      value: el.value,
      placeholder: el.getAttribute("placeholder"),
      style: {
        position: style.position,
        left: style.left,
        top: style.top,
        width: style.width,
        height: style.height,
        opacity: style.opacity,
        visibility: style.visibility,
        display: style.display,
        clip: style.clip,
        overflow: style.overflow,
      },
      rect: { x: rect.x, y: rect.y, w: rect.width, h: rect.height },
      parentId: el.parentElement?.id || null,
      parentTag: el.parentElement?.tagName || null,
      dataset: Object.assign({}, el.dataset),
    };
  });
});
console.log("ALL inputs:", JSON.stringify(allInputs, null, 2));

// Also check for any canvas
const canvases = await p.evaluate(() => {
  return Array.from(document.querySelectorAll("canvas")).map(c => ({
    width: c.width,
    height: c.height,
    styleWidth: c.style.width,
    styleHeight: c.style.height,
    rect: c.getBoundingClientRect(),
  }));
});
console.log("Canvases:", JSON.stringify(canvases, null, 2));

await b.close();
