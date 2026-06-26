export async function generateKeyPair(): Promise<{ privateKey: CryptoKey; publicKeyB64: string }> {
  const pair = await crypto.subtle.generateKey('X25519', true, ['deriveBits']);
  const exportedPub = await crypto.subtle.exportKey('raw', pair.publicKey);

  const publicKeyB64 = btoa(String.fromCharCode(...new Uint8Array(exportedPub)));

  return { privateKey: pair.privateKey, publicKeyB64 };
}

export async function loadOrCreateKeyPair(): Promise<{ privateKey: CryptoKey; publicKeyB64: string }> {
  return generateKeyPair();
}

export async function deriveSharedSecret(
  myPrivateKey: CryptoKey,
  theirPublicKeyB64: string,
): Promise<ArrayBuffer> {
  const theirRaw = Uint8Array.from(atob(theirPublicKeyB64), (c) => c.charCodeAt(0));
  const theirPublicKey = await crypto.subtle.importKey(
    'raw',
    theirRaw,
    { name: 'X25519' },
    false,
    [],
  );
  return crypto.subtle.deriveBits(
    { name: 'X25519', public: theirPublicKey },
    myPrivateKey,
    256,
  );
}
