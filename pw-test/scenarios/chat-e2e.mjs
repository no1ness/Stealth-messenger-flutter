import { POCKETBASE_URL } from "../config.mjs";
import { readContactBundle } from "../contact-bundle-helper.mjs";
import { delay, enableFlutterA11y, typeIntoFlutterTextField } from "../core/flutter-helpers.mjs";
import { pbId, decodeBundle, registerUser } from "../core/scenario-helpers.mjs";

async function bridgeCall(page, cmd, ...args) {
  const noResult = ["addContact"];
  return page.evaluate(async ([cmd, args, noResult]) => {
    const fn = window.__test[cmd];
    if (typeof fn !== "function") throw new Error(`Bridge cmd "${cmd}" not found`);
    window.__test._result = undefined;
    fn(...args);
    if (noResult) return "ok";
    for (let i = 0; i < 200; i++) {
      await new Promise(r => setTimeout(r, 50));
      if (window.__test._result !== undefined) {
        const r = window.__test._result;
        window.__test._result = undefined;
        return r;
      }
    }
    throw new Error(`Bridge cmd "${cmd}" timed out after 10s`);
  }, [cmd, args, noResult.includes(cmd)]);
}

export default async function chatE2E({ alice, bob }) {
  alice.page.on("pageerror", err => console.log("[alice:error]", err.message, err.stack?.slice(0,200)));
  bob.page.on("pageerror", err => console.log("[bob:error]", err.message, err.stack?.slice(0,200)));
  alice.page.on("crash", () => console.log("[alice:crash] PAGE CRASHED"));
  bob.page.on("crash", () => console.log("[bob:crash] PAGE CRASHED"));
  alice.page.on("close", () => console.log("[alice:close] PAGE CLOSED"));
  bob.page.on("close", () => console.log("[bob:close] PAGE CLOSED"));
  const suffix = Date.now().toString(36);
  const nickA = "E2EAlice_" + suffix;
  const nickB = "E2EBob_" + suffix;

  console.log("[e2e] === Phase 1: register users ===");
  await registerUser(alice, nickA);
  await registerUser(bob, nickB);

  console.log("[e2e] === Phase 2: read contact bundles ===");
  const aliceBundle = await readContactBundle(alice.page);
  const bobBundle = await readContactBundle(bob.page);
  if (!aliceBundle || !bobBundle) throw new Error("Failed to read contact bundles");
  const aliceData = decodeBundle(aliceBundle);
  const bobData = decodeBundle(bobBundle);
  const alicePid = pbId(aliceData.user_id);
  const bobPid = pbId(bobData.user_id);
  console.log(`[e2e] Alice: ${alicePid} (${nickA})`);
  console.log(`[e2e] Bob:   ${bobPid} (${nickB})`);

  console.log("[e2e] === Phase 3: upload profiles to PB ===");
  const adminResp = await fetch(`${POCKETBASE_URL}/api/admins/auth-with-password`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ identity: "test@stealth.local", password: "testpass123" }),
  });
  if (!adminResp.ok) throw new Error("Admin auth failed");
  const adminData = await adminResp.json();
  const adminToken = adminData.token;
  if (!adminToken) throw new Error("No admin token in response");
  console.log("[e2e] admin token obtained");
  const upsert = async (uid, pubkey) => {
    const r = await fetch(`${POCKETBASE_URL}/api/collections/user_profiles/records`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: adminToken },
      body: JSON.stringify({ userId: uid, publicKey: pubkey, isOnline: true, platform: "web" }),
    });
    if (!r.ok) console.warn(`[e2e] profile upsert status ${r.status}`);
    return r;
  };
  await Promise.all([upsert(alicePid, aliceData.public_key), upsert(bobPid, bobData.public_key)]);
  console.log("[e2e] profiles uploaded");

  console.log("[e2e] === Phase 4: add contacts via bridge ===");
  await bridgeCall(alice.page, "searchUsers", bobBundle);
  await bridgeCall(alice.page, "addContact", bobData.user_id);
  console.log("[e2e] Alice added Bob");
  await bridgeCall(bob.page, "searchUsers", aliceBundle);
  await bridgeCall(bob.page, "addContact", aliceData.user_id);
  console.log("[e2e] Bob added Alice");

  console.log("[e2e] === Phase 5: create private chats via IndexedDB ===");
  async function createChatViaIndexedDB(page, myUserId, otherUserId) {
    return page.evaluate(async ({myUserId, otherUserId}) => {
      const open = indexedDB.open("stealth_local_v3.db");
      const db = await new Promise((res, rej) => {
        open.onsuccess = () => res(open.result);
        open.onerror = () => rej(open.error);
      });
      const existing = await new Promise((res, rej) => {
        const t = db.transaction("chats", "readonly");
        const r = t.objectStore("chats").getAll();
        r.onsuccess = () => res(r.result);
        r.onerror = () => rej(r.error);
      });
      for (const chat of existing) {
        if (chat.is_private && chat.members.length === 2 &&
            chat.members.includes(myUserId) && chat.members.includes(otherUserId)) {
          db.close();
          return chat.id;
        }
      }
      const chatId = crypto.randomUUID();
      const now = new Date().toISOString();
      await new Promise((res, rej) => {
        const t = db.transaction("chats", "readwrite");
        t.objectStore("chats").put({ id: chatId, name: null, is_private: true, members: [myUserId, otherUserId], created_at: now, updated_at: now, last_read_at: now });
        t.oncomplete = () => { db.close(); res(); };
        t.onerror = () => rej(t.error);
      });
      return chatId;
    }, { myUserId, otherUserId });
  }
  const aliceChatId = await createChatViaIndexedDB(alice.page, aliceData.user_id, bobData.user_id);
  if (!aliceChatId) throw new Error("createChat returned no chatId for Alice");
  console.log(`[e2e] Alice chat: ${aliceChatId}`);
  const bobChatId = await createChatViaIndexedDB(bob.page, bobData.user_id, aliceData.user_id);
  if (!bobChatId) throw new Error("createChat returned no chatId for Bob");
  console.log(`[e2e] Bob chat:   ${bobChatId}`);

  console.log("[e2e] === Phase 6: reload Alice to refresh chat list ===");
  await alice.page.reload({ waitUntil: "commit" });
  const a11yOk = await enableFlutterA11y(alice.page, 15000);
  if (!a11yOk) throw new Error("a11y not available after reload");
  const chatsTab = alice.page.getByRole("button", { name: /Chats|Чаты/i });
  await chatsTab.waitFor({ state: "visible", timeout: 15000 });
  console.log("[e2e] Alice reloaded, Chats tab visible");

  // DEBUG: snapshot page structure
  const allRoles = await alice.page.evaluate(() => {
    const els = document.querySelectorAll('[role]');
    return Array.from(els).map(e => e.getAttribute('role') + ':' + (e.textContent || '').slice(0, 60));
  });
  console.log("[e2e] DEBUG roles:", JSON.stringify(allRoles.slice(0, 20)));

  console.log("[e2e] === Phase 7: Alice sends encrypted message via UI ===");
  const chatTile = alice.page.getByRole("button", { name: new RegExp(nickB, "i") });
  await chatTile.waitFor({ state: "visible", timeout: 10000 }).catch(async () => {
    console.log("[e2e] DEBUG: chat tile NOT found, full role list:");
    const roles2 = await alice.page.evaluate(() => {
      const els = document.querySelectorAll('[role]');
      return Array.from(els).map(e => e.getAttribute('role') + ':' + (e.textContent || '').slice(0, 80));
    });
    console.log(JSON.stringify(roles2));
    throw new Error("chat tile not visible");
  });
  await chatTile.click();
  await delay(3000);

  const testMsg = "Hello Bob! This is an E2E encrypted message! " + suffix;
  await typeIntoFlutterTextField(alice.page, testMsg);
  await delay(800);

  const sendBtn = alice.page.getByRole("button", { name: /Send message/i });
  await sendBtn.waitFor({ state: "visible", timeout: 5000 });
  console.log("[e2e] send button visible, starting Bob's listener...");

  const [received] = await Promise.all([
    bridgeCall(bob.page, "waitForEvent", "MessageReceived", "30000"),
    (async () => {
      await delay(300);
      await sendBtn.click();
      console.log("[e2e] message sent via UI");
    })(),
  ]);

  if (received) {
    console.log(`[e2e] SUCCESS: Bob received message! ${JSON.stringify(received)}`);
  } else {
    console.log("[e2e] FAIL: Bob did not receive message within timeout");
  }

  console.log("[e2e] === done ===");
}
