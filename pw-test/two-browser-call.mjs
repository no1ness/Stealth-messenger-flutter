import { chromium } from "playwright";
import * as crypto from "crypto";
import { readContactBundle } from "./contact-bundle-helper.mjs";
import { WEB_URL, LAUNCH_ARGS, POCKETBASE_URL } from "./config.mjs";
import { delay, enableFlutterA11y, gotoApp, typeIntoFlutterTextField } from "./core/flutter-helpers.mjs";

const BASE = WEB_URL;
const suffix = Date.now().toString(36);

async function registerUser(page, nickname) {
  await gotoApp(page, BASE);

  const a11yReady = await enableFlutterA11y(page);
  if (!a11yReady) throw new Error("a11y did not become available");

  const nicknameField = page.getByRole("textbox").first();
  await nicknameField.waitFor({ state: "visible", timeout: 15_000 });
  await typeIntoFlutterTextField(page, nickname);

  const startButton = page.getByRole("button", { name: /НАЧАТЬ|GET STARTED/i });
  for (let attempt = 0; attempt < 15; attempt++) {
    if (await startButton.isEnabled()) break;
    await delay(200);
  }
  await startButton.click({ noWaitAfter: true });

  await page
    .getByRole("button", { name: "Chats" })
    .waitFor({ state: "visible", timeout: 60_000 });
}

async function readUserIdFromProfile(page) {
  return readContactBundle(page);
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    args: LAUNCH_ARGS,
  });

  const ctxA = await browser.newContext({
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    viewport: { width: 900, height: 800 },
  });
  const ctxB = await browser.newContext({
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    viewport: { width: 900, height: 800 },
  });

  const alice = await ctxA.newPage();
  const bob = await ctxB.newPage();

  const nickA = `Alice_${suffix}`;
  const nickB = `Bob_${suffix}`;

  console.log("Registering Bob…");
  await registerUser(bob, nickB);
  const bobBundle = await readUserIdFromProfile(bob);
  await bob.getByRole("button", { name: "Chats" }).click({ force: true, noWaitAfter: true });

  console.log("Registering Alice…");
  await registerUser(alice, nickA);
  const aliceBundle = await readUserIdFromProfile(alice);

  const decodeBundle = (raw) => {
    const b64 = raw.replace(/^stealth:/, "");
    return JSON.parse(Buffer.from(b64, "base64").toString());
  };
  const aliceData = decodeBundle(aliceBundle);
  const bobData = decodeBundle(bobBundle);
  const pbId = (uuid) =>
    crypto.createHash("sha256").update(uuid).digest("hex").substring(0, 15);
  const alicePbId = pbId(aliceData.user_id);
  const bobPbId = pbId(bobData.user_id);

  const aliceToken = await alice.evaluate(async () => {
    const readToken = async () => {
      for (let i = 0; i < 30; i++) {
        if (window.stealthCrypto) break;
        await new Promise((r) => setTimeout(r, 200));
      }
      if (!window.stealthCrypto) return null;
      const raw = localStorage.getItem("flutter.pb_token");
      if (!raw) return null;
      let enc;
      try { enc = JSON.parse(raw); } catch (_) { enc = raw; }
      try { return await window.stealthCrypto.decrypt(enc); } catch (_) { return null; }
    };
    for (let attempt = 0; attempt < 10; attempt++) {
      const token = await readToken();
      if (token) return token;
      await new Promise((r) => setTimeout(r, 500));
    }
    return null;
  });
  if (!aliceToken) throw new Error("PB token not found for Alice");

  const roomId = crypto.randomUUID();

  const dummySdp = [
    "v=0", "o=- 0 0 IN IP4 0.0.0.0", "s=-", "t=0 0",
    "a=group:BUNDLE 0", "a=msid-semantic: WMS",
    "m=audio 9 UDP/TLS/RTP/SAVPF 0", "c=IN IP4 0.0.0.0",
    "a=mid:0", "a=msid:stream1 audio1", "a=sendrecv", "a=rtcp-mux",
    "a=ice-ufrag:dummy", "a=ice-pwd:dummy",
    "a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00",
    "a=setup:actpass", "a=rtpmap:0 PCMU/8000",
  ].join("\r\n");

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
  if (!offerResp.ok) throw new Error(`PB offer POST failed (${offerResp.status}): ${await offerResp.text()}`);
  console.log("Offer sent");

  console.log("Waiting for incoming call on Bob…");
  const answerBtn = bob.getByRole("button", { name: /Answer|Ответить/i });
  await answerBtn.waitFor({ state: "visible", timeout: 30_000 });
  await answerBtn.click({ force: true, noWaitAfter: true });
  console.log("Answer clicked");

  try {
    await bob
      .getByText(/Подключение|Звонок/i)
      .first()
      .waitFor({ state: "visible", timeout: 15_000 });
    console.log("Bob sees call screen");
  } catch {
    console.log("Call status text not found (dummy SDP expected)");
  }

  console.log("Test completed");
  await browser.close();
}

main().catch((err) => {
  console.error("Test failed:", err?.message ?? err);
  process.exit(1);
});
