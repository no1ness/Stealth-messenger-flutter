import { test, expect, delay, enableA11y, registerUser } from "./helpers.js";

test.describe("Registration", () => {
  test("user can register with nickname", async ({ page }) => {
    const suffix = Date.now().toString(36);
    const nickname = `TestUser_${suffix}`;

    await registerUser(page, nickname);

    const chatsBtn = page.getByRole("button", { name: "Chats" });
    await expect(chatsBtn).toBeVisible({ timeout: 30_000 });
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
    await textbox.type("TempUser");

    const startBtn = page.getByRole("button", { name: /GET STARTED|НАЧАТЬ/i });
    await expect(startBtn).toBeEnabled({ timeout: 10_000 });
  });
});
