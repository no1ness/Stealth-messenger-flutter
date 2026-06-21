import { test as base, expect } from "@playwright/test";

const BASE_URL = process.env.STEALTH_WEB_URL || "http://127.0.0.1:58585";

export const test = base.extend({
  page: async ({ page }, use) => {
    await page.goto(BASE_URL, { waitUntil: "domcontentloaded", timeout: 30_000 });
    await enableA11y(page);
    await use(page);
  },
});

export { expect };

export async function delay(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

export async function enableA11y(page, deadlineMs = 30_000) {
  const deadline = Date.now() + deadlineMs;

  while (Date.now() < deadline) {
    const textboxes = await page.getByRole("textbox").count();
    const startButtons = await page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i }).count();
    const chatsButtons = await page.getByRole("button", { name: "Chats" }).count();

    if (textboxes > 0 || startButtons > 0 || chatsButtons > 0) {
      return true;
    }

    const clicked = await page.evaluate(() => {
      const btn = document.querySelector(
        '[aria-label="Enable accessibility"], flt-semantics-placeholder',
      );
      if (!btn) return false;
      btn.click();
      return true;
    });

    if (clicked) {
      for (let i = 0; i < 10; i++) {
        await delay(500);
        const counts = await Promise.all([
          page.getByRole("textbox").count(),
          page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i }).count(),
          page.getByRole("button", { name: "Chats" }).count(),
        ]);
        if (counts.some((c) => c > 0)) return true;
      }
    } else {
      await delay(500);
    }
  }

  return false;
}

export async function registerUser(page, nickname) {
  const isRegistered = await page.getByRole("button", { name: "Chats" }).isVisible().catch(() => false);
  if (isRegistered) return;

  const a11yReady = await enableA11y(page);
  if (!a11yReady) throw new Error("a11y not available");

  const tf = page.getByRole("textbox").first();
  await tf.waitFor({ state: "visible", timeout: 15_000 });
  await tf.click();
  await tf.type(nickname);

  const startButton = page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i });
  for (let i = 0; i < 20; i++) {
    if (await startButton.isEnabled()) break;
    await delay(200);
  }
  await startButton.click();

  await page.getByRole("button", { name: "Chats" }).waitFor({ state: "visible", timeout: 60_000 });
}

export async function goToTab(page, tabName) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const btn = page.getByRole("button", { name: tabName });
      await btn.waitFor({ state: "visible", timeout: 8_000 });
      await btn.click();
      await delay(1000);
      return true;
    } catch {
      if (attempt < 2) await delay(1000);
    }
  }
  return false;
}
