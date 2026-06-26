import { test, expect, delay, enableA11y } from "./helpers.js";
import { gotoApp, enableFlutterA11y } from "../core/flutter-helpers.mjs";

const BASE_URL = process.env.STEALTH_WEB_URL || "http://127.0.0.1:58585";

test.describe("Registration", () => {
  test("user can register with nickname", async ({ page }) => {
    test.setTimeout(240_000);

    const suffix = Date.now().toString(36);
    const nickname = `TestUser_${suffix}`;

    // Register via test bridge (bypass UI unreliability with CanvasKit)
    await page.waitForFunction(() => typeof window.__test?.register === "function", {}, { timeout: 30_000 });
    await page.evaluate((n) => window.__test.register(n), nickname);

    // Bridge registration triggers window.location.reload() on success.
    // The reload navigates away briefly then back. Poll until that happens.
    for (let attempt = 0; attempt < 30; attempt++) {
      const url = page.url();
      if (!url.includes(BASE_URL)) break;
      await delay(500);
    }

    // Load the freshly-registered user's main screen
    await gotoApp(page, BASE_URL);

    // On desktop layout the main screen has a search textbox "Поиск"
    await enableFlutterA11y(page, 30_000);

    const searchBox = page.getByRole("textbox", { name: /Поиск|Search/i });
    await expect(searchBox).toBeVisible({ timeout: 30_000 });
  });

  test("registration screen shows input and start button", async ({ page }) => {
    await enableA11y(page);

    const textbox = page.getByRole("textbox").first();
    await expect(textbox).toBeVisible({ timeout: 15_000 });

    const startBtn = page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i });
    await expect(startBtn).toBeVisible({ timeout: 10_000 });
  });

  test("start button enables after typing nickname", async ({ page }) => {
    await enableA11y(page);

    const textbox = page.getByRole("textbox").first();
    await textbox.waitFor({ state: "visible", timeout: 15_000 });
    await textbox.click();
    await textbox.fill("TempUser");

    const startBtn = page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i });
    await expect(startBtn).toBeEnabled({ timeout: 10_000 });
  });
});