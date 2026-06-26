import { test, expect, delay, registerUser } from "./helpers.js";
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

  test("both users can read their contact bundles", async () => {
    const aliceBundle = await readContactBundle(alice);
    expect(aliceBundle).toBeTruthy();
    expect(aliceBundle).toMatch(/^stealth:/);

    const bobBundle = await readContactBundle(bob);
    expect(bobBundle).toBeTruthy();
    expect(bobBundle).toMatch(/^stealth:/);
  });

  test("contact bundles contain valid JSON payload", async () => {
    const aliceBundle = await readContactBundle(alice);
    const b64 = aliceBundle.replace(/^stealth:/, "");
    const payload = JSON.parse(Buffer.from(b64, "base64").toString());

    expect(payload).toHaveProperty("user_id");
    expect(payload).toHaveProperty("public_key");
    expect(payload.name || payload.nickname).toMatch(/^ContactAlice_/);
  });
});
