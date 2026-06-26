import { test as base, expect } from "@playwright/test";
import {
  delay,
  enableFlutterA11y,
  gotoApp,
  typeIntoFlutterTextField,
} from "../core/flutter-helpers.mjs";

const BASE_URL = process.env.STEALTH_WEB_URL || "http://127.0.0.1:58585";

export const test = base.extend({
  page: async ({ page }, use) => {
    await gotoApp(page, BASE_URL);
    await enableFlutterA11y(page, 30_000);
    await use(page);
  },
});

export { expect, delay };

export async function enableA11y(page, deadlineMs = 30_000) {
  const textboxes = await page.getByRole("textbox").count();
  const startButtons = await page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i }).count();
  const chatsButtons = await page.getByRole("button", { name: /Chats|Чаты/i }).count();

  if (textboxes > 0 || startButtons > 0 || chatsButtons > 0) {
    return true;
  }

  return enableFlutterA11y(page, deadlineMs);
}

export async function registerUser(page, nickname) {
  const isRegistered = await page.getByRole("button", { name: /Chats|Чаты/i }).isVisible().catch(() => false);
  if (isRegistered) return;

  // Only goto if the page isn't already loaded
  const hasContent = await page.evaluate(() => document.body?.innerHTML?.length > 0).catch(() => false);
  if (!hasContent) {
    await gotoApp(page, BASE_URL);
  }

  await enableA11y(page);

  const tf = page.getByRole("textbox").first();
  await tf.waitFor({ state: "visible", timeout: 30_000 });
  await tf.click();
  await typeIntoFlutterTextField(page, nickname);

  const startButton = page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i });
  await expect(startButton).toBeEnabled({ timeout: 10_000 });
  await startButton.click({ force: true, noWaitAfter: true });

  // After registration, wait for Chats button with periodic a11y refresh
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    const visible = await page.getByRole("button", { name: /Chats|Чаты/i }).isVisible().catch(() => false);
    if (visible) return;
    await enableFlutterA11y(page, 5_000);
    await delay(1000);
  }
  throw new Error("Chats button did not appear after registration");
}

const TAB_ALIASES = {
  Chats: /Chats|Чаты/i,
  Чаты: /Chats|Чаты/i,
  Calls: /Calls|Звонки/i,
  Звонки: /Calls|Звонки/i,
};

export async function goToTab(page, tabName) {
  const nameRe = TAB_ALIASES[tabName] || new RegExp(tabName, 'i');
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const btn = page.getByRole("button", { name: nameRe });
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
