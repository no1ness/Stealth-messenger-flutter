import { chromium } from 'playwright';
import { WEB_URL, LAUNCH_ARGS } from './config.mjs';

const browser = await chromium.launch({
  headless: true,
  args: LAUNCH_ARGS,
});
const page = await browser.newPage({ viewport: { width: 900, height: 800 } });
page.on("console", msg => { if (["log","error"].includes(msg.type())) console.log("["+msg.type()+"]", msg.text().substring(0,150)); });

await page.goto(WEB_URL, { waitUntil: "domcontentloaded", timeout: 15000 });
console.log("DOM loaded");

for (let t = 1; t <= 30; t++) {
  const btn = await page.evaluate(() => {
    const el = document.querySelector("[aria-label='Enable accessibility'], flt-semantics-placeholder");
    if (el) { el.click(); return "CLICKED"; }
    return "NOT_FOUND";
  });
  if (btn === "CLICKED") console.log("A11Y toggle clicked at", t, "s");

  const inputs = await page.evaluate(() => document.querySelectorAll("input").length);
  if (inputs > 0) {
    console.log("Found inputs at", t, "s");

    // Try keyboard.type()
    const input = page.getByRole("textbox").first();
    await input.click();
    await new Promise(r => setTimeout(r, 500));
    await page.keyboard.type("TestUser", { delay: 100 });
    await new Promise(r => setTimeout(r, 1000));

    const val = await page.evaluate(() => {
      const inp = document.querySelector("input");
      return inp ? inp.value : "no input";
    });
    console.log("Input value after keyboard.type:", JSON.stringify(val));

    const btnEnabled = await page.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled().catch(() => "err");
    console.log("Button enabled:", btnEnabled);

    // Also try evaluate setting value + dispatching input event
    console.log("Trying evaluate approach...");
    await page.evaluate(() => {
      const inp = document.querySelector('input');
      if (!inp) return;
      const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      nativeInputValueSetter.call(inp, 'UserViaNativeSetter_42');
      inp.dispatchEvent(new Event('input', { bubbles: true }));
      inp.dispatchEvent(new Event('change', { bubbles: true }));
    });
    await new Promise(r => setTimeout(r, 1000));
    
    const val2 = await page.evaluate(() => {
      const inp = document.querySelector("input");
      return inp ? inp.value : "no input";
    });
    console.log("After native setter:", JSON.stringify(val2));
    const btnEnabled2 = await page.getByRole("button", { name: /НАЧАТЬ/i }).isEnabled().catch(() => "err");
    console.log("Button enabled after setter:", btnEnabled2);

    break;
  }
  await new Promise(r => setTimeout(r, 1000));
}

await browser.close();
