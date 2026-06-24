import { test, expect, delay, registerUser, goToTab } from "./helpers.js";
import { readContactBundle } from "../contact-bundle-helper.mjs";
import { POCKETBASE_URL } from "../config.mjs";

test.describe("Chat", () => {
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
      registerUser(alice, `ChatAlice_${suffix}`),
      registerUser(bob, `ChatBob_${suffix}`),
    ]);
  });

  test.afterEach(async () => {
    await alice?.context().close();
    await bob?.context().close();
  });

  test("both users see Chats tab after registration", async () => {
    await expect(alice.getByRole("button", { name: /Chats|Чаты/i })).toBeVisible();
    await expect(bob.getByRole("button", { name: /Chats|Чаты/i })).toBeVisible();
  });

  test("user can navigate to Contacts tab", async () => {
    // Contacts are now inside the Chats screen; navigate via sidebar tabs
    const navigated = await goToTab(alice, "Чаты");
    expect(navigated).toBe(true);
    // Within Chats, click the Контакты sidebar tab
    const contactsTab = alice.getByRole("tab", { name: /Contacts|Контакты/i });
    await contactsTab.waitFor({ state: "visible", timeout: 8_000 });
    await contactsTab.click();

    const addContactBtn = alice.getByRole("button", { name: /Add contact|Добавить контакт|Добавить/i });
    await expect(addContactBtn.first()).toBeVisible({ timeout: 10_000 });
  });

  test("contact bundle can be read", async () => {
    const bundle = await readContactBundle(alice);
    expect(bundle).toBeTruthy();
    expect(bundle).toMatch(/^stealth:/);
  });
});
