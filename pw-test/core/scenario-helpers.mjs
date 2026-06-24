import crypto from "crypto";
import { Buffer } from "buffer";
import { enableFlutterA11y, typeIntoFlutterTextField, delay } from "./flutter-helpers.mjs";

export function pbId(uuid) {
  return crypto.createHash("sha256").update(uuid).digest("hex").substring(0, 15);
}

export const dummySdp = [
  "v=0", "o=- 0 0 IN IP4 0.0.0.0", "s=-", "t=0 0",
  "a=group:BUNDLE 0", "a=msid-semantic: WMS",
  "m=audio 9 UDP/TLS/RTP/SAVPF 0", "c=IN IP4 0.0.0.0",
  "a=mid:0", "a=msid:stream1 audio1", "a=sendrecv", "a=rtcp-mux",
  "a=ice-ufrag:dummy", "a=ice-pwd:dummy",
  "a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00",
  "a=setup:actpass", "a=rtpmap:0 PCMU/8000",
].join("\r\n");

export function decodeBundle(raw) {
  const b64 = raw.replace(/^stealth:/, "");
  return JSON.parse(Buffer.from(b64, "base64").toString());
}

export async function readPbToken(page) {
  return page.evaluate(async () => {
    const readToken = async () => {
      for (let i = 0; i < 30; i++) {
        if (typeof window.stealthCrypto !== "undefined") break;
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
}

export async function registerUser(client, nickname) {
  // Check if already registered first (Chats screen has a search textbox)
  const isRegistered = await client.page.getByRole("button", { name: /Chats|Чаты/i }).isVisible().catch(() => false);
  if (isRegistered) {
    console.log(`[reg] ${nickname} already registered, skipping`);
    return;
  }

  const a11yReady = await enableFlutterA11y(client.page, 15000);
  if (!a11yReady) throw new Error("a11y not available for " + nickname);

  const hasField = await client.page.getByRole("textbox").first().isVisible().catch(() => false);
  if (!hasField) {
    throw new Error("Nickname field not visible for " + nickname);
  }

  await typeIntoFlutterTextField(client.page, nickname);

  const startBtn = client.page.getByRole("button", { name: /НАЧАТЬ|GET STARTED/i });
  for (let attempt = 0; attempt < 15; attempt++) {
    if (await startBtn.isEnabled()) break;
    await delay(200);
  }
  await startBtn.click({ force: true, noWaitAfter: true });

  await client.page
    .getByRole("button", { name: /Chats|Чаты/i })
    .waitFor({ state: "visible", timeout: 60000 });
  console.log(`[reg] ${nickname} registered`);
}
