/**
 * Diagnostic: inspect Flutter-web DOM structure so we can find correct selectors.
 *
 * Prerequisites:
 *   cd client
 *   flutter run -d web-server --web-hostname=127.0.0.1 --web-port=57575
 *
 * Run (from pw-test/):
 *   node diagnose-web.mjs
 */
import { chromium } from "playwright";
import { writeFileSync } from "fs";
import { WEB_URL } from "./config.mjs";

const BASE = WEB_URL;
const TIMEOUT = 120_000;

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForApp(page) {
  const deadline = Date.now() + TIMEOUT;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      await page.goto(BASE, { waitUntil: "networkidle", timeout: 20_000 });
      console.log("✅ Page loaded (networkidle)");
      return;
    } catch (e) {
      lastErr = e;
      console.log(`⏳ Waiting for server… (${e.message.slice(0, 60)})`);
      await delay(3000);
    }
  }
  throw new Error(`Could not reach ${BASE}: ${lastErr?.message}`);
}

/** Force-click the hidden Flutter accessibility toggle via JS evaluation. */
async function enableFlutterA11y(page) {
  const result = await page.evaluate(() => {
    const btn = document.querySelector(
      '[aria-label="Enable accessibility"], flt-semantics-placeholder',
    );
    if (!btn) return "NOT_FOUND";
    btn.click();
    return "CLICKED";
  });
  console.log("enableFlutterA11y result:", result);
  return result === "CLICKED";
}

/** Dump all elements with any aria-* attribute. */
async function dumpAriaElements(page, label) {
  console.log(
    `\n── ${label} ─────────────────────────────────────────────────`,
  );
  const els = await page
    .locator("[aria-label], [aria-placeholder], [role], [aria-roledescription]")
    .all();
  console.log(`  Total elements with ARIA attrs: ${els.length}`);
  for (const el of els.slice(0, 60)) {
    const tag = await el.evaluate((n) => n.tagName.toLowerCase());
    const role = await el.getAttribute("role").catch(() => null);
    const label2 = await el.getAttribute("aria-label").catch(() => null);
    const ph = await el.getAttribute("aria-placeholder").catch(() => null);
    const roledesc = await el
      .getAttribute("aria-roledescription")
      .catch(() => null);
    const visible = await el.isVisible().catch(() => false);
    // Only print elements that carry meaningful info
    if (role || label2 || ph) {
      console.log(
        `  <${tag}> role=${role ?? "-"}  label=${label2 ?? "-"}  ph=${ph ?? "-"}  roledesc=${roledesc ?? "-"}  visible=${visible}`,
      );
    }
  }
}

async function dumpInputs(page, label) {
  console.log(
    `\n── ${label}: inputs/textboxes ────────────────────────────────`,
  );
  const inputs = await page.locator('input, textarea, [role="textbox"]').all();
  console.log(`  Found ${inputs.length}`);
  for (const inp of inputs) {
    const tag = await inp.evaluate((n) => n.tagName.toLowerCase());
    const type = await inp.getAttribute("type").catch(() => null);
    const ariaLabel = await inp.getAttribute("aria-label").catch(() => null);
    const ph = await inp.getAttribute("placeholder").catch(() => null);
    const visible = await inp.isVisible().catch(() => false);
    console.log(
      `  <${tag}> type=${type ?? "-"}  aria-label=${ariaLabel ?? "-"}  placeholder=${ph ?? "-"}  visible=${visible}`,
    );
  }
}

async function dumpButtons(page, label) {
  console.log(
    `\n── ${label}: buttons ─────────────────────────────────────────`,
  );
  const btns = await page.locator('[role="button"], button').all();
  console.log(`  Found ${btns.length}`);
  for (const btn of btns.slice(0, 30)) {
    const tag = await btn.evaluate((n) => n.tagName.toLowerCase());
    const ariaLabel = await btn.getAttribute("aria-label").catch(() => null);
    const text = await btn.innerText().catch(() => null);
    const visible = await btn.isVisible().catch(() => false);
    const display = (ariaLabel ?? text ?? "").trim().slice(0, 80);
    if (display) console.log(`  <${tag}> visible=${visible}  "${display}"`);
  }
}

async function dumpFltSemantics(page, label) {
  console.log(
    `\n── ${label}: flt-semantics ────────────────────────────────────`,
  );
  const els = await page.locator("flt-semantics").all();
  console.log(`  Found ${els.length} flt-semantics elements`);
  for (const el of els.slice(0, 50)) {
    const role = await el.getAttribute("role").catch(() => null);
    const ariaLabel = await el.getAttribute("aria-label").catch(() => null);
    const ph = await el.getAttribute("aria-placeholder").catch(() => null);
    const tag = await el.evaluate((n) => n.tagName.toLowerCase());
    if (role || ariaLabel || ph) {
      console.log(
        `  <${tag}> role=${role ?? "-"}  label=${ariaLabel ?? "-"}  ph=${ph ?? "-"}`,
      );
    }
  }
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    args: [
      "--use-fake-ui-for-media-stream",
      "--use-fake-device-for-media-stream",
    ],
  });

  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    // fresh storage – no prior user registration
  });
  const page = await ctx.newPage();

  // ── 1. Open app ───────────────────────────────────────────────────────────────
  await waitForApp(page);
  console.log("⏳ Waiting 5 s for Flutter CanvasKit bootstrap…");
  await delay(5000);

  // ── 2. Screenshot: initial state ─────────────────────────────────────────────
  await page.screenshot({ path: "diag-01-initial.png", fullPage: true });
  console.log("📸 diag-01-initial.png");

  // ── 3. DOM before enabling accessibility ─────────────────────────────────────
  await dumpAriaElements(page, "BEFORE a11y");
  await dumpInputs(page, "BEFORE a11y");
  await dumpButtons(page, "BEFORE a11y");
  await dumpFltSemantics(page, "BEFORE a11y");

  // ── 4. Enable Flutter accessibility via JS (element is off-screen) ────────────
  console.log(
    "\n── Enabling Flutter accessibility via JS evaluation… ────────",
  );
  const clicked = await enableFlutterA11y(page);
  if (!clicked) {
    console.warn(
      '  ⚠️  accessibility toggle not found – trying Tab+Enter fallback',
    );
    await page.keyboard.press("Tab");
    await delay(300);
    await page.keyboard.press("Enter");
  }

  // Give Flutter time to build the semantic tree
  console.log("⏳ Waiting 5 s for semantic tree to populate…");
  await delay(5000);

  // ── 5. Screenshot: after accessibility enabled ────────────────────────────────
  await page.screenshot({ path: "diag-02-after-a11y.png", fullPage: true });
  console.log("📸 diag-02-after-a11y.png");

  // ── 6. DOM after enabling accessibility ──────────────────────────────────────
  await dumpAriaElements(page, "AFTER a11y");
  await dumpInputs(page, "AFTER a11y");
  await dumpButtons(page, "AFTER a11y");
  await dumpFltSemantics(page, "AFTER a11y");

  // ── 7. Accessibility snapshot (Playwright built-in) ───────────────────────────
  console.log(
    "\n── Playwright accessibility snapshot ────────────────────────",
  );
  let snap;
  try {
    snap = await page.accessibility.snapshot({ interestingOnly: true });
  } catch (e) {
    snap = { error: e.message };
  }
  writeFileSync("diag-a11y-after.json", JSON.stringify(snap, null, 2));
  console.log("♿ diag-a11y-after.json written");

  // ── 8. Full page HTML after a11y ─────────────────────────────────────────────
  const html = await page.content();
  writeFileSync("diag-page-after.html", html);
  console.log(`🗂  diag-page-after.html (${html.length} bytes)`);

  // ── 9. Try filling the nickname field ────────────────────────────────────────
  console.log("\n── Attempting to fill nickname field… ──────────────────────");

  // Strategy A: getByRole textbox
  let filled = false;
  try {
    const tb = page.getByRole("textbox").first();
    await tb.waitFor({ state: "attached", timeout: 5000 });
    await tb.fill("TestUser123");
    console.log("✅ Strategy A (getByRole textbox): filled");
    filled = true;
  } catch (e) {
    console.log("❌ Strategy A failed:", e.message.slice(0, 80));
  }

  // Strategy B: aria-label containing "alias"
  if (!filled) {
    try {
      const inp = page.locator('[aria-label*="alias" i]').first();
      await inp.waitFor({ state: "attached", timeout: 5000 });
      await inp.fill("TestUser123");
      console.log("✅ Strategy B (aria-label*=alias): filled");
      filled = true;
    } catch (e) {
      console.log("❌ Strategy B failed:", e.message.slice(0, 80));
    }
  }

  // Strategy C: any visible <input>
  if (!filled) {
    try {
      const inp = page.locator("input").first();
      await inp.waitFor({ state: "attached", timeout: 5000 });
      await inp.fill("TestUser123");
      console.log("✅ Strategy C (input): filled");
      filled = true;
    } catch (e) {
      console.log("❌ Strategy C failed:", e.message.slice(0, 80));
    }
  }

  // Strategy D: click canvas by coordinate then type
  if (!filled) {
    console.log(
      "↳ Strategy D: click canvas at estimated input position + keyboard type",
    );
    // From screenshot: input field is at approximately y=525 (center of 1280x900)
    await page.mouse.click(640, 525);
    await delay(500);
    await page.keyboard.type("TestUser123");
    console.log("✅ Strategy D (coordinate click + type): typed");
    filled = true;
  }

  await page.screenshot({ path: "diag-03-filled.png", fullPage: true });
  console.log("📸 diag-03-filled.png");

  // ── 10. Try clicking GET STARTED button ──────────────────────────────────────
  console.log("\n── Attempting to click GET STARTED button… ─────────────────");

  let btnClicked = false;

  // Strategy A: getByRole button with name
  try {
    const btn = page.getByRole("button", { name: /GET STARTED/i });
    await btn.waitFor({ state: "attached", timeout: 5000 });
    await btn.click({ force: true });
    console.log("✅ GET STARTED btn via getByRole: clicked");
    btnClicked = true;
  } catch (e) {
    console.log("❌ GET STARTED getByRole failed:", e.message.slice(0, 80));
  }

  // Strategy B: aria-label
  if (!btnClicked) {
    try {
      const btn = page.locator('[aria-label*="GET STARTED" i]').first();
      await btn.waitFor({ state: "attached", timeout: 3000 });
      await btn.click({ force: true });
      console.log("✅ GET STARTED btn via aria-label: clicked");
      btnClicked = true;
    } catch (e) {
      console.log("❌ GET STARTED aria-label failed:", e.message.slice(0, 80));
    }
  }

  // Strategy C: coordinate click (button is below input, ~y=590)
  if (!btnClicked) {
    console.log("↳ GET STARTED: coordinate click at y=590");
    await page.mouse.click(640, 590);
    console.log("✅ GET STARTED coord click done");
  }

  await delay(3000);
  await page.screenshot({ path: "diag-04-after-submit.png", fullPage: true });
  console.log("📸 diag-04-after-submit.png");

  // ── 11. Dump DOM after potential navigation ───────────────────────────────────
  await dumpAriaElements(page, "AFTER submit");
  await dumpButtons(page, "AFTER submit");

  await browser.close();

  console.log("\n✅ Diagnostics complete.");
  console.log(
    "   Files: diag-01-initial.png, diag-02-after-a11y.png, diag-03-filled.png, diag-04-after-submit.png",
  );
  console.log("          diag-a11y-after.json, diag-page-after.html");
}

main().catch((err) => {
  console.error("\n❌ Diagnostic failed:", err.message ?? err);
  process.exit(1);
});
