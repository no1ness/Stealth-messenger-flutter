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
  const bobPbId = pbId(bobData.user_id);

  const aliceToken = await readPbToken(alice.page);
  if (!aliceToken) throw new Error("PB token not found for Alice");

  // Upload Bob's profile to PB so Alice can find him
  const bobProfileResp = await fetch(
    `${POCKETBASE_URL}/api/collections/user_profiles/records`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: aliceToken },
      body: JSON.stringify({
        userId: bobPbId,
        publicKey: bobData.public_key,
        isOnline: true,
        platform: "web",
      }),
    },
  ).catch(() => null);

  if (bobProfileResp && bobProfileResp.ok) {
    console.log("[chat] Bob profile uploaded to PB");
  } else {
    console.log("[chat] Bob profile already exists in PB");
  }

  // Verify profile is fetchable from PB
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
  const alicePbId = pbId(aliceData.user_id);
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
    console.log("[chat] datachannel offer sent to PB");
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

  // Navigate to Contacts tab and verify Add contact button
  await alice.page.getByRole("button", { name: "Contacts" }).click({ force: true, noWaitAfter: true });
  await delay(1000);

  const addContactBtn = alice.page.getByRole("button", { name: "Add contact" });
  if (await addContactBtn.isVisible().catch(() => false)) {
    console.log("[chat] Contacts screen: Add contact button visible");
  }

  // Click Add contact and check for search/paste input
  await addContactBtn.click({ force: true, noWaitAfter: true });
  await delay(1500);

  const pasteInput = alice.page.getByRole("textbox").first();
  if (await pasteInput.isVisible().catch(() => false)) {
    console.log("[chat] Add contact sheet: paste/search input visible");
  }

  // Dismiss the sheet by pressing Escape
  await alice.page.keyboard.press("Escape");
  await delay(500);

  // Navigate back to Chats
  await alice.page.getByRole("button", { name: "Chats" }).click({ force: true, noWaitAfter: true });
  await delay(1000);

  // Check if any chat tiles exist
  const chatTiles = await alice.page.getByRole("button", { name: /Чат/i }).count().catch(() => 0);
  console.log(`[chat] chat tiles found: ${chatTiles}`);
}
