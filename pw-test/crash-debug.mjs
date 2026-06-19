import { chromium } from 'playwright';
import { readContactBundle } from './contact-bundle-helper.mjs';
import { WEB_URL } from './config.mjs';

const delay = ms => new Promise(r => setTimeout(r, ms));
const BASE = WEB_URL;

async function typeInto(page, text) {
  const f = page.getByRole("textbox").first();
  await f.focus();
  await delay(300);
  await page.keyboard.press("ArrowRight");
  await delay(200);
  await page.evaluate((txt) => {
    const inp = document.querySelector("input");
    if (!inp) return;
    inp.value = "";
    for (let i = 0; i < txt.length; i++) {
      const ch = txt[i];
      inp.value += ch;
      inp.dispatchEvent(new InputEvent("beforeinput", { inputType: "insertText", data: ch, bubbles: true }));
      inp.dispatchEvent(new InputEvent("input", { inputType: "insertText", data: ch, bubbles: true }));
    }
    inp.dispatchEvent(new Event("change", { bubbles: true }));
  }, text);
  await delay(500);
}

const b = await chromium.launch({
  headless: true,
  args: ["--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream"],
});

const ctx = await b.newContext({ permissions: ["microphone","camera","clipboard-read","clipboard-write"], viewport: { width:900, height:800 } });
const p = await ctx.newPage();

// Monitor crashes and errors
p.on("crash", () => console.log(">> PAGE CRASHED <<"));
p.on("close", () => console.log(">> PAGE CLOSED <<"));
p.on("pageerror", err => console.log(">> Page error:", err.message?.substring(0,100)));
p.on("console", m => {
  const txt = m.text();
  if (m.type() === "error") console.log("[ERR]", txt.substring(0,200));
  else if (m.type() === "log") console.log("[log]", txt.substring(0,200));
});

// Register user
for (let t = 1; t <= 20; t++) {
  try { await p.goto(BASE, { waitUntil: "domcontentloaded", timeout: 15000 }); break; }
  catch(e) { await delay(2000); }
}
for (let t = 1; t <= 30; t++) {
  await p.evaluate(() => {
    const el = document.querySelector('[aria-label="Enable accessibility"]') || document.querySelector('flt-semantics-placeholder');
    if (el) el.click();
  });
  if (await p.evaluate(() => !!document.querySelector("input"))) break;
  await delay(1000);
}
console.log("Registered...");
await typeInto(p, "TestUser_42");
await p.getByRole("button", { name: /НАЧАТЬ/i }).click();
await p.getByRole("button", { name: /Chats/i }).waitFor({ state: "visible", timeout: 60000 });
console.log("On main screen");

// Get user bundle
const bundle = await readContactBundle(p);
console.log("Bundle:", bundle?.substring(0,50));

// Navigate to Contacts and Add contact
await p.getByRole("button", { name: /Contacts/i }).click();
await delay(1000);
await p.getByRole("button", { name: /Add contact/i }).last().click();
await delay(1000);

// Write bundle to clipboard
await p.evaluate((id) => {
  const ta = document.createElement("textarea");
  ta.value = id;
  document.body.appendChild(ta);
  ta.select();
  document.execCommand("copy");
  document.body.removeChild(ta);
}, bundle);
console.log("Bundle written to clipboard");

// Find search field
const searchField = p.getByRole("textbox").first();
await searchField.waitFor({ state: "visible", timeout: 10000 }).catch(() => {});
await delay(500);

// Click Paste contact
const pasteBtn = p.getByRole("button", { name: /Вставить контакт/i });
const pasteCount = await pasteBtn.count();
console.log("Paste button count:", pasteCount);
if (pasteCount > 0) {
  await pasteBtn.click();
  console.log("Pasted, waiting for results...");
}

await delay(5000);

// Check the semantics tree now
const sem = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  return Array.from(host.querySelectorAll("flt-semantics")).slice(-10).map(s => ({
    text: s.textContent?.substring(0, 40),
    role: s.getAttribute("data-semantics-role"),
    label: s.getAttribute("aria-label"),
  }));
});
console.log("Semantics after paste:", JSON.stringify(sem, null, 2));

// Try clicking Save contact via evaluate (not Playwright)
console.log("Clicking Save contact via evaluate...");
await p.evaluate(() => {
  const btn = document.querySelector('[aria-label="Save contact"]');
  console.log("Save button found?", !!btn);
  if (btn) btn.click();
});
console.log("After evaluate click, page still alive");

await delay(3000);
console.log("Still alive after 3s");

// Check if we navigated somewhere new
const sem2 = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  return Array.from(host.querySelectorAll("flt-semantics")).slice(-5).map(s => ({
    text: s.textContent?.substring(0, 40),
  }));
}).catch(e => "evaluate error: " + e.message?.substring(0,60));
console.log("After pop:", JSON.stringify(sem2, null, 2));

await b.close();
