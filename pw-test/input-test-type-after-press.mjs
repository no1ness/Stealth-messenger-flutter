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
  if (await p.evaluate(() => document.querySelector('input') !== null)) { console.log("Ready at", t, "s"); break; }
  await new Promise(r => setTimeout(r, 1000));
}

const input = p.getByRole("textbox").first();
await input.focus();
await new Promise(r => setTimeout(r, 300));

// Wake up Flutter
await p.keyboard.press("ArrowRight");
await new Promise(r => setTimeout(r, 200));

// Can we use keyboard.type() now?
console.log("Testing keyboard.type after wake...");
await p.keyboard.type("KeyboardType_after_wakeup", { delay: 50 });
await new Promise(r => setTimeout(r, 2000));

const r1 = await p.evaluate(() => ({
  buttonDisabled: (() => {
    const host = document.querySelector("flt-semantics-host");
    if (!host) return "no host";
    const all = Array.from(host.querySelectorAll("flt-semantics"));
    const button = all.find(s => s.textContent === "НАЧАТЬ");
    return button?.getAttribute("aria-disabled");
  })(),
  inputValue: document.querySelector("input")?.value,
}));
console.log("After keyboard.type:", JSON.stringify(r1));
const enabled1 = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled();
console.log("Button enabled:", enabled1);

await b.close();
