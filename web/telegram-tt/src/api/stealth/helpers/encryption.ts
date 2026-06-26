const MK_LABEL = new Uint8Array([0x01]);
const CK_LABEL = new Uint8Array([0x02]);

export interface EncryptedPayload {
  version: 1;
  nonce: string;
  ciphertext: string;
  messageKeyId: number;
}

function copySlice(src: Uint8Array, start: number, end?: number): Uint8Array {
  return new Uint8Array(src.slice(start, end ?? src.length));
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const r = new Uint8Array(a.length + b.length);
  r.set(a);
  r.set(b, a.length);
  return r;
}

function b64enc(d: Uint8Array): string {
  return btoa(String.fromCharCode(...d));
}

function b64dec(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

async function hmacSign(key: CryptoKey, data: BufferSource): Promise<ArrayBuffer> {
  return crypto.subtle.sign('HMAC', key, data);
}

export class EncryptedSession {
  private chainKey: CryptoKey | undefined;
  private mkId = 0;
  private secret: ArrayBuffer | undefined;

  async initWithSecret(sharedSecret: ArrayBuffer): Promise<void> {
    this.secret = sharedSecret;
    const hmacParams = { name: 'HMAC', hash: 'SHA-256' } as const;
    this.chainKey = await crypto.subtle.importKey('raw', sharedSecret, hmacParams, false, ['sign']);
  }

  async encrypt(plain: string): Promise<EncryptedPayload> {
    if (!this.chainKey) throw new Error('Session not ready');

    const mkBuf = await hmacSign(this.chainKey, MK_LABEL);
    const ckBuf = await hmacSign(this.chainKey, CK_LABEL);
    const hmacArgs = { name: 'HMAC', hash: 'SHA-256' } as const;
    this.chainKey = await crypto.subtle.importKey('raw', ckBuf, hmacArgs, false, ['sign']);

    const aesKey = await crypto.subtle.importKey('raw', mkBuf, 'AES-GCM', false, ['encrypt']);
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const encoded = new TextEncoder().encode(plain);
    const aesParams = { name: 'AES-GCM', iv: nonce, tagLength: 128 } as const;
    const raw = new Uint8Array(
      await crypto.subtle.encrypt(aesParams, aesKey, encoded),
    );

    const ct = copySlice(raw, 0, -16);
    const tag = copySlice(raw, -16);

    return {
      version: 1,
      nonce: b64enc(nonce),
      ciphertext: b64enc(concat(ct, tag)),
      messageKeyId: this.mkId++,
    };
  }

  async decrypt(payload: EncryptedPayload): Promise<string> {
    if (!this.secret) throw new Error('Session not ready');
    const nonce = b64dec(payload.nonce) as Uint8Array<ArrayBuffer>;
    const combined = b64dec(payload.ciphertext) as Uint8Array<ArrayBuffer>;

    const aesKey = await crypto.subtle.importKey('raw', this.secret, 'AES-GCM', false, ['decrypt']);
    const raw = new Uint8Array(await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce, tagLength: 128 },
      aesKey,
      combined,
    ));

    return new TextDecoder().decode(raw);
  }

  isReady(): boolean {
    return Boolean(this.chainKey);
  }
}
