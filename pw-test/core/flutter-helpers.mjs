/**
 * Flutter Web (CanvasKit) helper functions for E2E tests
 * 
 * Provides common utilities for:
 * - Bootstrap state checking
 * - Accessibility (semantics) enabling
 * - Text input into Flutter text fields
 * - App navigation
 */

export const delay = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Check Flutter bootstrap state
 */
export async function getBootstrapState(page) {
  return page.evaluate(() => ({
    hasA11yToggle: !!document.querySelector(
      '[aria-label="Enable accessibility"], flt-semantics-placeholder',
    ),
    hasTextbox: !!document.querySelector('input, textarea, [role="textbox"]'),
    hasLoadingIndicator: !!document.querySelector("#loading_indicator"),
    bodyLength: document.body?.innerHTML?.length ?? 0,
    hasDebugRunMain: typeof window.$dartRunMain === "function",
    dartMainExecuted: !!window.$dartMainExecuted,
  }));
}

/**
 * Kick debug main if needed (for Flutter web debug mode)
 */
export async function kickDebugMainIfNeeded(page) {
  return page.evaluate(() => {
    if (!window.$dartMainExecuted && typeof window.$dartRunMain === "function") {
      window.$dartRunMain();
      return true;
    }
    return false;
  });
}

/**
 * Enable Flutter accessibility/semantics layer
 * Required for CanvasKit rendering to expose DOM elements
 */
export async function enableFlutterA11y(page, deadlineMs = 30000) {
  const deadline = Date.now() + deadlineMs;

  while (Date.now() < deadline) {
    const textboxCount = await page.getByRole("textbox").count();
    const startButtonCount = await page
      .getByRole("button", { name: /НАЧАТЬ|GET STARTED/i })
      .count();
    const chatsButtonCount = await page.getByRole("button", { name: "Chats" }).count();

    if (textboxCount > 0 || startButtonCount > 0 || chatsButtonCount > 0) {
      return true;
    }

    const result = await page.evaluate(() => {
      const btn = document.querySelector(
        '[aria-label="Enable accessibility"], flt-semantics-placeholder',
      );
      if (!btn) return "NOT_FOUND";
      btn.click();
      return "CLICKED";
    });

    if (result === "CLICKED") {
      for (let attempt = 0; attempt < 10; attempt++) {
        await delay(1000);
        const textboxes = await page.getByRole("textbox").count();
        const startButtons = await page
          .getByRole("button", { name: /НАЧАТЬ|GET STARTED/i })
          .count();
        const chatsButtons = await page.getByRole("button", { name: "Chats" }).count();
        if (textboxes > 0 || startButtons > 0 || chatsButtons > 0) {
          return true;
        }
      }
    } else {
      await delay(1000);
    }
  }

  return false;
}

/**
 * Navigate to app with retry logic
 */
export async function gotoApp(page, baseUrl, deadlineMs = 120000) {
  const deadline = Date.now() + deadlineMs;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 15000 });
      for (let attempt = 0; attempt < 20 && Date.now() < deadline; attempt++) {
        const state = await getBootstrapState(page);
        if (state.hasA11yToggle || state.hasTextbox) {
          return;
        }
        if (state.hasDebugRunMain && !state.dartMainExecuted) {
          await kickDebugMainIfNeeded(page);
        }
        await delay(1000);
      }

      await page.reload({ waitUntil: "domcontentloaded", timeout: 15000 });
    } catch (e) {
      lastErr = e;
      await delay(2000);
    }
  }
  throw new Error(
    `Failed to reach ${baseUrl}. Last error: ${lastErr?.message || lastErr}`,
  );
}

/**
 * Type text into Flutter CanvasKit text field
 * Playwright .fill() and .type() don't work with CanvasKit semantics inputs.
 * Solution: send trusted keydown to activate Flutter engine, then insert each character
 * via InputEvent + beforeinput.
 */
export async function typeIntoFlutterTextField(page, text) {
  const field = page.getByRole("textbox").first();
  await field.focus();
  await delay(300);

  // Trigger input connector with trusted event
  await page.keyboard.press("ArrowRight");
  await delay(200);

  // Insert text character by character via evaluate
  await page.evaluate(async (txt) => {
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const inp = document.querySelector("input");
    if (!inp) return;
    inp.value = "";
    for (let i = 0; i < txt.length; i++) {
      const ch = txt[i];
      inp.value += ch;
      inp.dispatchEvent(new InputEvent("beforeinput", {
        inputType: "insertText", data: ch, bubbles: true,
      }));
      inp.dispatchEvent(new InputEvent("input", {
        inputType: "insertText", data: ch, bubbles: true,
      }));
      await sleep(10);
    }
    inp.dispatchEvent(new Event("change", { bubbles: true }));
  }, text);
  await delay(500);
}

/**
 * Reset page to main Chats screen
 * page.reload() is the most reliable way to exit any sub-screen in Flutter web
 */
export async function resetToMain(page, baseUrl) {
  await gotoApp(page, baseUrl);
  await delay(2000);
  await enableFlutterA11y(page);
  
  try {
    await page
      .getByRole("button", { name: "Chats" })
      .waitFor({ state: "visible", timeout: 30000 });
  } catch (error) {
    console.warn(`Chats button not found after reset: ${error.message}`);
    await delay(3000);
    await enableFlutterA11y(page);
    await page
      .getByRole("button", { name: "Chats" })
      .waitFor({ state: "visible", timeout: 20000 });
  }
  await delay(500);
}
