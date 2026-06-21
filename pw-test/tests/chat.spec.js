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
    await expect(alice.getByRole("button", { name: "Chats" })).toBeVisible();
    await expect(bob.getByRole("button", { name: "Chats" })).toBeVisible();
  });

  test("user can navigate to Contacts tab", async () => {
    const navigated = await goToTab(alice, "Contacts");
    expect(navigated).toBe(true);

    const addContactBtn = alice.getByRole("button", { name: /Add contact/i });
    await expect(addContactBtn.first()).toBeVisible({ timeout: 10_000 });
  });

  test("contact bundle can be read", async () => {
    const bundle = await readContactBundle(alice);
    expect(bundle).toBeTruthy();
    expect(bundle).toMatch(/^stealth:/);
  });
});
