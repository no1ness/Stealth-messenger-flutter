export async function sharedSecretFromX25519(
  myPrivateKey: CryptoKey,
  theirPublicKey: CryptoKey,
): Promise<ArrayBuffer> {
  return crypto.subtle.deriveBits(
    { name: 'X25519', public: theirPublicKey },
    myPrivateKey,
    256,
  );
}

export async function aes256GcmDecrypt(
  encryptedBase64: string,
  keyBytes: ArrayBuffer,
  iv?: Uint8Array,
): Promise<ArrayBuffer> {
  const encryptedArr = Uint8Array.from(atob(encryptedBase64), (c) => c.charCodeAt(0));
  const nonce: Uint8Array<ArrayBuffer> = (iv ?? encryptedArr.slice(0, 12)) as Uint8Array<ArrayBuffer>;
  const ciphertext = iv ? encryptedArr : encryptedArr.slice(12);
  const tag = ciphertext.slice(-16);
  const actualCiphertext = ciphertext.slice(0, -16);

  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt']);

  const combined: Uint8Array<ArrayBuffer> = new Uint8Array([...actualCiphertext, ...tag]);
  return crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 },
    key,
    combined,
  );
}

export async function aes256GcmEncrypt(
  plaintext: ArrayBuffer,
  keyBytes: ArrayBuffer,
): Promise<string> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, ['encrypt']);

  const encrypted = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 },
    key,
    plaintext,
  );

  const encryptedArr = new Uint8Array(encrypted);
  const ciphertext = encryptedArr.slice(0, -16);
  const tag = encryptedArr.slice(-16);

  const combined = new Uint8Array([...nonce, ...ciphertext, ...tag]);
  return btoa(String.fromCharCode(...combined));
}

export async function ratchetGetMessageKey(
  chainKeyBase64: string,
  index: number,
): Promise<{ messageKey: string; nextChainKey: string }> {
  const chainKeyBytes = Uint8Array.from(atob(chainKeyBase64), (c) => c.charCodeAt(0));

  const signingKey = await crypto.subtle.importKey(
    'raw',
    chainKeyBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    true,
    ['sign'],
  );

  const msgLabel: Uint8Array<ArrayBuffer> = new Uint8Array([0x01]);
  const chainLabel: Uint8Array<ArrayBuffer> = new Uint8Array([0x02]);
  const msgKeyBuf = await crypto.subtle.sign('HMAC', signingKey, msgLabel);
  const nextChainKeyBuf = await crypto.subtle.sign('HMAC', signingKey, chainLabel);

  const msgKey = btoa(String.fromCharCode(...new Uint8Array(msgKeyBuf)));
  const nextChainKey = btoa(String.fromCharCode(...new Uint8Array(nextChainKeyBuf)));

  return { messageKey: msgKey, nextChainKey };
}
