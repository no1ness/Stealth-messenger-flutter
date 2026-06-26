export const kPbIdLength = 15;

function isCanonicalUuid(s: string): boolean {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(s);
}

export async function pbIdFromLocalUuid(localUuid: string): Promise<string> {
  if (isCanonicalUuid(localUuid)) {
    const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(localUuid));
    const hex = Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join('');
    return hex.slice(0, kPbIdLength);
  }
  return localUuid.length > kPbIdLength ? localUuid.slice(0, kPbIdLength) : localUuid;
}
