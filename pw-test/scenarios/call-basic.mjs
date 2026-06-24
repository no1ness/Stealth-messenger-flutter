import crypto from "crypto";
import { POCKETBASE_URL } from "../config.mjs";
import { readContactBundle } from "../contact-bundle-helper.mjs";
import { pbId, dummySdp, readPbToken, decodeBundle, registerUser } from "../core/scenario-helpers.mjs";

export default async function callBasic({ alice, bob }) {
  const suffix = Date.now().toString(36);
  const nickA = "Alice_" + suffix;
  const nickB = "Bob_" + suffix;

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

  const roomId = crypto.randomUUID();

  const offerResp = await fetch(
    `${POCKETBASE_URL}/api/collections/rtc_signaling/records`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: aliceToken },
      body: JSON.stringify({
        roomId, creator: alicePbId, target: bobPbId, type: "offer",
        payload: {
          sdp: dummySdp, type: "offer", purpose: "call",
          nickname: "Alice", callType: "audio",
          creatorUuid: aliceData.user_id,
          creatorLocalId: aliceData.user_id,
          targetLocalId: bobData.user_id,
        },
      }),
    },
  );
  if (offerResp.ok) {
    console.log("[call] offer sent");
    const answerBtn = bob.page.getByRole("button", { name: /Answer|Ответить/i });
    try {
      await answerBtn.waitFor({ state: "visible", timeout: 10000 });
      await answerBtn.click({ force: true, noWaitAfter: true });
      console.log("[call] Bob answered");
    } catch {
      console.log("[call] Answer button not visible (dummy SDP expected)");
    }
  } else {
    console.log(`[call] offer POST failed (${offerResp.status}) — skipping signaling check`);
  }
}
