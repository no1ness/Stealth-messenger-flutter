export async function generateX25519KeyPair(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits', 'deriveKey']);
}

export async function exportKeyBase64(key: CryptoKey): Promise<string> {
  const raw = await crypto.subtle.exportKey('raw', key);
  return btoa(String.fromCharCode(...new Uint8Array(raw)));
}

export async function importX25519PrivateKey(base64Key: string): Promise<CryptoKey> {
  const raw = Uint8Array.from(atob(base64Key), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('raw', raw, { name: 'X25519' }, true, ['deriveBits']);
}

export async function importX25519PublicKey(base64Key: string): Promise<CryptoKey> {
  const raw = Uint8Array.from(atob(base64Key), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('raw', raw, { name: 'X25519' }, true, []);
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
