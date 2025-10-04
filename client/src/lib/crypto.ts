export async function generateKeyPair() {
  const keyPair = await window.crypto.subtle.generateKey(
    {
      name: "RSA-OAEP",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["encrypt", "decrypt"]
  );
  
  return keyPair;
}

export async function exportPublicKey(publicKey: CryptoKey): Promise<string> {
  const exported = await window.crypto.subtle.exportKey("spki", publicKey);
  const exportedAsBase64 = btoa(String.fromCharCode(...new Uint8Array(exported)));
  return exportedAsBase64;
}

export async function exportPrivateKey(privateKey: CryptoKey): Promise<string> {
  const exported = await window.crypto.subtle.exportKey("pkcs8", privateKey);
  const exportedAsBase64 = btoa(String.fromCharCode(...new Uint8Array(exported)));
  return exportedAsBase64;
}

export async function importPublicKey(base64Key: string): Promise<CryptoKey> {
  const binaryString = atob(base64Key);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  
  return await window.crypto.subtle.importKey(
    "spki",
    bytes.buffer,
    {
      name: "RSA-OAEP",
      hash: "SHA-256",
    },
    true,
    ["encrypt"]
  );
}

export async function importPrivateKey(base64Key: string): Promise<CryptoKey> {
  const binaryString = atob(base64Key);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  
  return await window.crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    {
      name: "RSA-OAEP",
      hash: "SHA-256",
    },
    true,
    ["decrypt"]
  );
}

export async function encryptMessage(message: string, publicKey: CryptoKey): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(message);
  
  const encrypted = await window.crypto.subtle.encrypt(
    {
      name: "RSA-OAEP",
    },
    publicKey,
    data
  );
  
  return btoa(String.fromCharCode(...new Uint8Array(encrypted)));
}

export async function decryptMessage(ciphertext: string, privateKey: CryptoKey): Promise<string> {
  const binaryString = atob(ciphertext);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  
  const decrypted = await window.crypto.subtle.decrypt(
    {
      name: "RSA-OAEP",
    },
    privateKey,
    bytes.buffer
  );
  
  const decoder = new TextDecoder();
  return decoder.decode(decrypted);
}

export function generateUserId(): string {
  return crypto.randomUUID();
}
