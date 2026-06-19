import { enableFlutterA11y, typeIntoFlutterTextField, delay } from "../core/flutter-helpers.mjs";

export default async function registration({ alice, bob, url }) {
  const nicknameA = "Alice_" + Date.now().toString(36);
  const nicknameB = "Bob_" + Date.now().toString(36);

  async function register(client, nickname) {
    const a11yReady = await enableFlutterA11y(client.page, 15000);
    if (!a11yReady) throw new Error("a11y not available for " + nickname);

    const hasField = await client.page.getByRole("textbox").first().isVisible().catch(() => false);
    if (!hasField) {
      const isRegistered = await client.page.getByRole("button", { name: "Chats" }).isVisible().catch(() => false);
      if (isRegistered) {
        console.log(`[reg] ${nickname} already registered, skipping`);
        return;
      }
      throw new Error("Nickname field not visible for " + nickname);
    }

    await typeIntoFlutterTextField(client.page, nickname);

    const startBtn = client.page.getByRole("button", { name: /НАЧАТЬ|GET STARTED/i });
    for (let attempt = 0; attempt < 15; attempt++) {
      if (await startBtn.isEnabled()) break;
      await delay(200);
    }
    await startBtn.click({ noWaitAfter: true });

    await client.page
      .getByRole("button", { name: "Chats" })
      .waitFor({ state: "visible", timeout: 60000 });
    console.log(`[reg] ${nickname} registered`);
  }

  const t0 = Date.now();
  await Promise.all([register(alice, nicknameA), register(bob, nicknameB)]);
  console.log(`[reg] both users registered in ${Date.now() - t0}ms`);
}
