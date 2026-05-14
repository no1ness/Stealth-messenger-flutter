export async function readContactBundle(page) {
  return page.evaluate(async () => {
    for (let i = 0; i < 40; i++) {
      if (window.stealthCrypto) break;
      await new Promise((resolve) => setTimeout(resolve, 300));
    }
    if (!window.stealthCrypto) return null;

    async function readSecureValue(key) {
      const raw = localStorage.getItem(`flutter.${key}`) ||
        localStorage.getItem(key);
      if (!raw) return null;
      let encrypted;
      try {
        encrypted = JSON.parse(raw);
      } catch (_) {
        encrypted = raw;
      }
      try {
        return await window.stealthCrypto.decrypt(encrypted);
      } catch (_) {
        return null;
      }
    }

    const userId = await readSecureValue("userId");
    const nickname = await readSecureValue("nickname");
    const publicKey = await readSecureValue("publicKey");
    if (!userId || !publicKey) return null;

    const payload = JSON.stringify({
      v: 1,
      user_id: userId,
      name: nickname || userId,
      public_key: publicKey,
    });
    const utf8 = new TextEncoder().encode(payload);
    let binary = "";
    utf8.forEach((byte) => {
      binary += String.fromCharCode(byte);
    });
    return `stealth:${btoa(binary)
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/g, "")}`;
  });
}
