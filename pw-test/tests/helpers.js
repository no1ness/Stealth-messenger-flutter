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

  await gotoApp(page, BASE_URL);

  const a11yReady = await enableA11y(page);
  if (!a11yReady) throw new Error("a11y not available");

  const tf = page.getByRole("textbox").first();
  await tf.waitFor({ state: "visible", timeout: 15_000 });
  await tf.click();
  await typeIntoFlutterTextField(page, nickname);

  const startButton = page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i });
  await expect(startButton).toBeEnabled({ timeout: 5000 });
  await startButton.click({ noWaitAfter: true });

  await page.getByRole("button", { name: /Chats|Чаты/i }).waitFor({ state: "visible", timeout: 60_000 });
}

const TAB_ALIASES = {
  Chats: /Chats|Чаты/i,
  Чаты: /Chats|Чаты/i,
  Contacts: /Contacts|Контакты/i,
  Контакты: /Contacts|Контакты/i,
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
