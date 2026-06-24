export const delay = (ms) => new Promise((r) => setTimeout(r, ms));

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

export async function kickDebugMainIfNeeded(page) {
  return page.evaluate(() => {
    if (!window.$dartMainExecuted && typeof window.$dartRunMain === "function") {
      window.$dartRunMain();
      return true;
    }
    return false;
  });
}

export async function enableFlutterA11y(page, deadlineMs = 10000) {
  if (await page.getByRole("textbox").count() > 0) return true;

  const deadline = Date.now() + deadlineMs;

  while (Date.now() < deadline) {
    const clicked = await page.evaluate(() => {
      const p = document.querySelector(
        'flt-semantics-placeholder[aria-label="Enable accessibility"], [aria-label="Enable accessibility"]',
      );
      if (!p) return false;
      p.click();
      return true;
    });

    if (clicked) {
      // Wait for textbox to appear after enabling a11y
      for (let i = 0; i < 20 && Date.now() < deadline; i++) {
        if (await page.getByRole("textbox").count() > 0) return true;
        await delay(100);
      }
    } else {
      await delay(200);
    }
  }

  return (await page.getByRole("textbox").count()) > 0;
}

export async function gotoApp(page, baseUrl, deadlineMs = 60000) {
  const deadline = Date.now() + deadlineMs;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 10000 });
      for (let attempt = 0; attempt < 20 && Date.now() < deadline; attempt++) {
        const state = await getBootstrapState(page);
        if (state.hasA11yToggle || state.hasTextbox) {
          return;
        }
        if (state.hasDebugRunMain && !state.dartMainExecuted) {
          await kickDebugMainIfNeeded(page);
        }
        await delay(300);
      }
      await page.reload({ waitUntil: "domcontentloaded", timeout: 10000 });
    } catch (e) {
      lastErr = e;
      await delay(1000);
    }
  }
  throw new Error(
    `Failed to reach ${baseUrl}. Last error: ${lastErr?.message || lastErr}`,
  );
}

export async function typeIntoFlutterTextField(page, text) {
  const field = page.getByRole("textbox").first();
  await field.focus();
  await delay(50);
  await page.keyboard.press("ArrowRight");
  await delay(50);

  await page.evaluate(async (txt) => {
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
    }
    inp.dispatchEvent(new Event("change", { bubbles: true }));
  }, text);
  await delay(120);
}

export async function resetToMain(page, baseUrl) {
  await gotoApp(page, baseUrl);
  await enableFlutterA11y(page);

  try {
    await page
      .getByRole("button", { name: /Chats|Чаты/i })
      .waitFor({ state: "visible", timeout: 15000 });
  } catch (error) {
    console.warn(`Chats button not found after reset: ${error.message}`);
    await enableFlutterA11y(page);
    await page
      .getByRole("button", { name: /Chats|Чаты/i })
      .waitFor({ state: "visible", timeout: 10000 });
  }
}
