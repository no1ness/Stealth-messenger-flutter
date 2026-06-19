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

for (let t = 1; t <= 50; t++) {
  await p.evaluate(() => {
    const el = document.querySelector('[aria-label="Enable accessibility"], flt-semantics-placeholder');
    if (el) el.click();
  });
  if (await p.evaluate(() => !!document.querySelector("input"))) break;
  await delay(1000);
}

// Register a user and go to contacts
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

await typeInto(p, "TestClick");
await p.getByRole("button", { name: /НАЧАТЬ/i }).click();
await p.getByRole("button", { name: /Chats/i }).waitFor({ state: "visible", timeout: 60000 });

// Examine glass-pane
const gp = await p.evaluate(() => {
  const pane = document.querySelector("flt-glass-pane");
  if (!pane) return null;
  const cs = getComputedStyle(pane);
  const parentCS = pane.parentElement ? getComputedStyle(pane.parentElement) : {};
  return {
    tag: pane.tagName,
    rect: pane.getBoundingClientRect(),
    parentTag: pane.parentElement?.tagName,
    style: {
      position: cs.position,
      pointerEvents: cs.pointerEvents,
      zIndex: cs.zIndex,
      overflow: cs.overflow,
      width: cs.width,
      height: cs.height,
    },
    parentStyle: {
      position: parentCS.position,
      pointerEvents: parentCS.pointerEvents,
      width: parentCS.width,
      height: parentCS.height,
    },
    hasListeners: pane.onpointerdown || pane.onmousedown ? true : false,
  };
});
console.log("Glass pane:", JSON.stringify(gp, null, 2));

// Try dispatching pointerdown/up directly on glass-pane
const pane = await p.evaluate(() => document.querySelector("flt-glass-pane"));

console.log("Adding listener at glass pane for mousedown...");
await p.evaluate(() => {
  const pane = document.querySelector("flt-glass-pane");
  if (pane) {
    pane.addEventListener("mousedown", e => console.log("GP mousedown", e.clientX, e.clientY));
    pane.addEventListener("mouseup", e => console.log("GP mouseup", e.clientX, e.clientY));
    pane.addEventListener("click", e => console.log("GP click", e.clientX, e.clientY));
    pane.addEventListener("pointerdown", e => console.log("GP pointerdown", e.clientX, e.clientY));
    pane.addEventListener("pointerup", e => console.log("GP pointerup", e.clientX, e.clientY));
  }
  const fv = document.querySelector("flutter-view");
  if (fv) {
    fv.addEventListener("mousedown", e => console.log("FV mousedown", e.clientX, e.clientY));
    fv.addEventListener("mouseup", e => console.log("FV mouseup", e.clientX, e.clientY));
  }
});

// Check event propagation chain with elementFromPoint
const chain = await p.evaluate(() => {
  const x = 200, y = 200;
  const el = document.elementFromPoint(x, y);
  let cur = el;
  const parents = [];
  while (cur) {
    const cs = getComputedStyle(cur);
    parents.push({
      tag: cur.tagName,
      pe: cs.pointerEvents,
      pos: cs.position,
      id: cur.id || "",
      class: (cur.className || "").slice(0, 30),
    });
    cur = cur.parentElement;
  }
  return { hit: el?.tagName, parents };
});
console.log("Hit test at (200,200):", JSON.stringify(chain, null, 2));

// Navigate to contacts
await p.getByRole("button", { name: /Contacts|Контакты/i }).click();
await delay(1000);
await p.getByRole("button", { name: /Add contact/i }).last().click();
await delay(1000);

// Paste bundle
const bundle = await p.evaluate(async () => {
  for (let i = 0; i < 40; i++) {
    if (window.stealthCrypto) break;
    await new Promise(r => setTimeout(r, 300));
  }
  async function readValue(key) {
    const raw = localStorage.getItem(`flutter.${key}`) || localStorage.getItem(key);
    if (!raw) return null;
    let enc;
    try { enc = JSON.parse(raw); } catch (_) { enc = raw; }
    try { return await window.stealthCrypto.decrypt(enc); } catch (_) { return null; }
  }
  const userId = await readValue("userId");
  const nickname = await readValue("nickname");
  const publicKey = await readValue("publicKey");
  if (!userId || !publicKey) return null;
  const pld = JSON.stringify({ v:1, user_id:userId, name:nickname||userId, public_key:publicKey });
  const utf8 = new TextEncoder().encode(pld);
  let bin = "";
  utf8.forEach(b => bin += String.fromCharCode(b));
  return `stealth:${btoa(bin).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,"")}`;
});

await p.evaluate((id) => {
  const ta = document.createElement("textarea");
  ta.value = id;
  document.body.appendChild(ta);
  ta.select();
  document.execCommand("copy");
  document.body.removeChild(ta);
}, bundle);

const searchField = p.getByRole("textbox").first();
await searchField.waitFor({ state: "visible", timeout: 10000 }).catch(() => {});
await p.getByRole("button", { name: /Вставить контакт/i }).click().catch(() => {});
await delay(5000);

// Get save button position
const btnPos = await p.evaluate(() => {
  const btn = document.querySelector('[aria-label*="Save contact"]');
  if (!btn) return null;
  const r = btn.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2, l: r.left, t: r.top, w: r.width, h: r.height };
});
console.log("Button position:", JSON.stringify(btnPos));

// Click on glass pane at button position
if (btnPos) {
  // Method 1: mouse.click
  console.log("\n=== Method 1: page.mouse.click ===");
  await p.mouse.click(btnPos.x, btnPos.y);
  await delay(2000);
  let stillOpen = await p.evaluate(() => !!document.querySelector('[aria-label="Contact bundle input"]'));
  console.log("  Modal open:", stillOpen);

  // Method 2: evaluate dispatch with pointer events on glass-pane
  if (stillOpen) {
    console.log("\n=== Method 2: pointer on glass-pane ===");
    await p.evaluate(({x, y}) => {
      const pane = document.querySelector("flt-glass-pane");
      if (!pane) return;
      pane.dispatchEvent(new PointerEvent("pointerdown", {
        clientX: x, clientY: y, bubbles: true, cancelable: true,
      }));
      pane.dispatchEvent(new PointerEvent("pointerup", {
        clientX: x, clientY: y, bubbles: true, cancelable: true,
      }));
    }, btnPos);
    await delay(2000);
    stillOpen = await p.evaluate(() => !!document.querySelector('[aria-label="Contact bundle input"]'));
    console.log("  Modal open:", stillOpen);
  }

  // Method 3: dispatch on flutter-view
  if (stillOpen) {
    console.log("\n=== Method 3: pointer on flutter-view ===");
    await p.evaluate(({x, y}) => {
      const fv = document.querySelector("flutter-view");
      if (!fv) return;
      fv.dispatchEvent(new PointerEvent("pointerdown", {
        clientX: x, clientY: y, bubbles: true, cancelable: true,
      }));
      fv.dispatchEvent(new PointerEvent("pointerup", {
        clientX: x, clientY: y, bubbles: true, cancelable: true,
      }));
    }, btnPos);
    await delay(2000);
    stillOpen = await p.evaluate(() => !!document.querySelector('[aria-label="Contact bundle input"]'));
    console.log("  Modal open:", stillOpen);
  }

  // Method 4: real Playwright mouse but with correct targeting
  if (stillOpen) {
    console.log("\n=== Method 4: mouse.down/mouse.up on exact coordinates ===");
    await p.mouse.move(btnPos.x, btnPos.y);
    await p.mouse.down();
    await delay(100);
    await p.mouse.up();
    await delay(2000);
    stillOpen = await p.evaluate(() => !!document.querySelector('[aria-label="Contact bundle input"]'));
    console.log("  Modal open:", stillOpen);
  }
}

await b.close();
