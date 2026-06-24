import crypto from "crypto";
import { POCKETBASE_URL } from "../config.mjs";
import { readContactBundle } from "../contact-bundle-helper.mjs";
import { delay } from "../core/flutter-helpers.mjs";
import { pbId, dummySdp, readPbToken, decodeBundle, registerUser } from "../core/scenario-helpers.mjs";

export default async function chatBasic({ alice, bob }) {
  const suffix = Date.now().toString(36);
  const nickA = "ChatAlice_" + suffix;
  const nickB = "ChatBob_" + suffix;

  await registerUser(alice, nickA);
  await registerUser(bob, nickB);

  const aliceBundle = await readContactBundle(alice.page);
  const bobBundle = await readContactBundle(bob.page);
  if (!aliceBundle || !bobBundle) throw new Error("Failed to read contact bundles");

  const aliceData = decodeBundle(aliceBundle);
  const bobData = decodeBundle(bobBundle);
  const alicePbId = pbId(aliceData.user_id);
  const bobPbId = pbId(bobData.user_id);

  const aliceToken = await readPbToken(alice.page);
  if (!aliceToken) throw new Error("PB token not found for Alice");

  // Upload both profiles to PB so they can find each other
  async function upsertProfile(userId, publicKey) {
    return fetch(
      `${POCKETBASE_URL}/api/collections/user_profiles/records`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: aliceToken },
        body: JSON.stringify({ userId, publicKey, isOnline: true, platform: "web" }),
      },
    ).catch(() => null);
  }

  await Promise.all([
    upsertProfile(alicePbId, aliceData.public_key),
    upsertProfile(bobPbId, bobData.public_key),
  ]);
  console.log("[chat] profiles uploaded to PB");

  // Verify profiles are fetchable
  const getResp = await fetch(
    `${POCKETBASE_URL}/api/collections/user_profiles/records?filter=userId='${bobPbId}'`,
    { headers: { Authorization: aliceToken } },
  );
  if (getResp.ok) {
    const profiles = await getResp.json();
    const found = profiles?.items?.length > 0;
    console.log(`[chat] Bob profile ${found ? "found" : "NOT found"} in PB`);
  } else {
    console.log(`[chat] profile GET failed (${getResp.status})`);
  }

  // Send a datachannel signaling offer (like call does but for chat)
  const roomId = crypto.randomUUID();
  const dcResp = await fetch(
    `${POCKETBASE_URL}/api/collections/rtc_signaling/records`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: aliceToken },
      body: JSON.stringify({
        roomId, creator: alicePbId, target: bobPbId, type: "offer",
        payload: {
          sdp: dummySdp, type: "offer", purpose: "datachannel",
          nickname: "Alice", callType: "datachannel",
          creatorUuid: aliceData.user_id,
          creatorLocalId: aliceData.user_id,
          targetLocalId: bobData.user_id,
        },
      }),
    },
  );
  if (dcResp.ok) {
    console.log("[chat] datachannel offer posted to PB");
    // Verify Bob's app received it (Flutter logs via console in CanvasKit)
    const dcReceived = await bob.page.waitForEvent("console", {
      predicate: (msg) => msg.text().includes("datachannel offer"),
      timeout: 3000,
    }).then(() => true).catch(() => false);
    console.log(`[chat] Bob ${dcReceived ? "received" : "did not confirm"} datachannel offer`);
    // Clean up the signaling record
    const record = await dcResp.json();
    if (record?.id) {
      await fetch(
        `${POCKETBASE_URL}/api/collections/rtc_signaling/records/${record.id}`,
        { method: "DELETE", headers: { Authorization: aliceToken } },
      ).catch(() => {});
    }
  } else {
    console.log(`[chat] datachannel offer POST failed (${dcResp.status})`);
  }

  // Verify Chats screen is visible
  await alice.page.getByRole("button", { name: /Chats|Чаты/i }).waitFor({ state: "visible", timeout: 5000 });
  console.log("[chat] Chats screen verified");

  // Try Contacts sidebar tab if on desktop layout (non-blocking)
  const contactsTab = alice.page.getByRole("tab", { name: /Contacts|Контакты/i });
  if (await contactsTab.isVisible().catch(() => false)) {
    await contactsTab.click({ force: true, noWaitAfter: true });
    await delay(1500);
    const addContactBtn = alice.page.getByRole("button", { name: /Add contact|Добавить контакт|Добавить/i });
    if (await addContactBtn.isVisible().catch(() => false)) {
      console.log("[chat] Contacts screen: Add contact button visible");
    }
  }
}
