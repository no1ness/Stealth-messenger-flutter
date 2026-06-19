/**
 * Decode a stealth:base64 contact bundle and write contact directly to IndexedDB.
 * Then reload the app so _loadContacts() picks it up on init.
 */
export async function addContactFromBundle(page, bundleRaw) {
  // 1. Decode bundle
  const contact = await page.evaluate(async (b64) => {
    const decoded = atob(b64.replace(/^stealth:/, "").replace(/-/g, "+").replace(/_/g, "/"));
    const obj = JSON.parse(decoded);
    const now = new Date().toISOString();
    return {
      contact_user_id: obj.user_id,
      user_id: obj.user_id,
      name: obj.name || obj.user_id,
      nickname: obj.name || obj.user_id,
      public_key: obj.public_key,
      created_at: now,
    };
  }, bundleRaw);

  // 2. Write to IndexedDB
  await page.evaluate(async (c) => {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open("stealth_local_v3.db", 7);
      req.onsuccess = () => {
        const db = req.result;
        const txn = db.transaction("contacts", "readwrite");
        const store = txn.objectStore("contacts");
        const putReq = store.put(c);
        putReq.onsuccess = () => { db.close(); resolve(); };
        putReq.onerror = () => { db.close(); reject(putReq.error); };
      };
      req.onerror = () => reject(req.error);
    });
  }, contact);

  // 3. Close modal via Escape key
  await page.keyboard.press("Escape");
  await new Promise(r => setTimeout(r, 2000));
}
