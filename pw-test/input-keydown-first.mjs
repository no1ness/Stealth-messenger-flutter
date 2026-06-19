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
  const hasInput = await p.evaluate(() => document.querySelector('input') !== null);
  if (hasInput) { console.log("Ready at", t, "s"); break; }
  await new Promise(r => setTimeout(r, 1000));
}

// KEY CHANGE: use page.keyboard to send a keydown first (trusted events)
// This might "wake up" Flutter's text input connection
const input = p.getByRole("textbox").first();
await input.focus();
await new Promise(r => setTimeout(r, 500));

// Send one real keyboard event to establish connection
await p.keyboard.press("ArrowRight");
await new Promise(r => setTimeout(r, 300));

// Now try evaluate-based typing
await p.evaluate(() => {
  const inp = document.querySelector("input");
  if (!inp) return;
  
  const text = "AliceWorks_42";
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    inp.value = inp.value + char;
    inp.dispatchEvent(new InputEvent('beforeinput', {
      inputType: 'insertText', data: char, bubbles: true,
    }));
    inp.dispatchEvent(new InputEvent('input', {
      inputType: 'insertText', data: char, bubbles: true,
    }));
  }
  inp.dispatchEvent(new Event('change', { bubbles: true }));
});

await new Promise(r => setTimeout(r, 3000));

const r = await p.evaluate(() => {
  const host = document.querySelector("flt-semantics-host");
  if (!host) return "no host";
  const all = Array.from(host.querySelectorAll("flt-semantics"));
  const button = all.find(s => s.textContent === "НАЧАТЬ");
  const textField = all.find(s => s.textContent === "");
  return {
    buttonDisabled: button?.getAttribute("aria-disabled"),
    inputValue: document.querySelector("input")?.value,
  };
});
console.log("After:", JSON.stringify(r));

const enabled = await p.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled().catch(() => "err");
console.log("Playwright enabled:", enabled);

if (enabled === true) {
  await p.getByRole("button", { name: /НАЧАТЬ/i }).click();
  await new Promise(r => setTimeout(r, 5000));
  const chatsTab = await p.getByRole("button", { name: /Chats/i }).count();
  console.log("Chats tab:", chatsTab > 0);
}

await b.close();
