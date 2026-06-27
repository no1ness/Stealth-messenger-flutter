export async function generateX25519KeyPair(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits', 'deriveKey']);
}

export async function exportKeyBase64(key: CryptoKey): Promise<string> {
  try {
    const jwk = await crypto.subtle.exportKey('jwk', key);
    return btoa(JSON.stringify(jwk));
  } catch (err) {
    console.error('[STEALTH] exportKeyBase64 failed for key type:', key.type, 'algorithm:', key.algorithm, err);
    throw err;
  }
}

export async function importX25519PrivateKey(base64Key: string): Promise<CryptoKey> {
  const jwk = JSON.parse(atob(base64Key));
  return crypto.subtle.importKey('jwk', jwk, { name: 'X25519' }, true, ['deriveBits']);
}

export async function importX25519PublicKey(base64Key: string): Promise<CryptoKey> {
  const jwk = JSON.parse(atob(base64Key));
  return crypto.subtle.importKey('jwk', jwk, { name: 'X25519' }, true, []);
}

function generatePassword(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const rand = new Uint8Array(24);
  crypto.getRandomValues(rand);
  return Array.from(rand).map((b) => chars[b % chars.length]).join('');
}

export function generateStealthUuid(): string {
  return crypto.randomUUID();
}

export function generatePbPassword(): string {
  return generatePassword();
}
