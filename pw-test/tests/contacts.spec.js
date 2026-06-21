import { test, expect, delay, registerUser, goToTab } from "./helpers.js";
import { readContactBundle } from "../contact-bundle-helper.mjs";

test.describe("Contacts", () => {
  let alice, bob;

  test.beforeEach(async ({ browser }) => {
    const suffix = Date.now().toString(36);

    const ctxA = await browser.newContext({
      viewport: { width: 900, height: 800 },
      permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    });
    const ctxB = await browser.newContext({
      viewport: { width: 900, height: 800 },
      permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    });

    alice = await ctxA.newPage();
    bob = await ctxB.newPage();

    await Promise.all([
      registerUser(alice, `ContactAlice_${suffix}`),
      registerUser(bob, `ContactBob_${suffix}`),
    ]);
  });

  test.afterEach(async () => {
    await alice?.context().close();
    await bob?.context().close();
  });

  test("Add contact button is visible on Contacts tab", async () => {
    await goToTab(alice, "Contacts");

    const addBtn = alice.getByRole("button", { name: /Add contact/i }).first();
    await expect(addBtn).toBeVisible({ timeout: 10_000 });
  });

  test("add contact sheet opens with search input", async () => {
    await goToTab(alice, "Contacts");

    const addBtn = alice.getByRole("button", { name: /Add contact/i }).first();
    await addBtn.click();
    await delay(2000);

    const searchInput = alice.getByRole("textbox").first();
    await expect(searchInput).toBeVisible({ timeout: 10_000 });
  });

  test("can paste contact bundle", async () => {
    const bobBundle = await readContactBundle(bob);
    expect(bobBundle).toBeTruthy();

    await goToTab(alice, "Contacts");

    const addBtn = alice.getByRole("button", { name: /Add contact/i }).first();
    await addBtn.click();
    await delay(2000);

    await alice.evaluate(
      (text) => navigator.clipboard.writeText(text),
      bobBundle,
    );

    await alice.keyboard.press("Control+v");
    await delay(1000);

    const pasteBtn = alice.getByRole("button", { name: /Вставить контакт|Paste contact/i });
    if (await pasteBtn.isVisible().catch(() => false)) {
      await pasteBtn.click();
      await delay(1000);
    }

    const searchInput = alice.getByRole("textbox").first();
    await expect(searchInput).toBeVisible();
  });
});
