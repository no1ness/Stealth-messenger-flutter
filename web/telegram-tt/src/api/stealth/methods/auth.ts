import PocketBase from 'pocketbase';

import { POCKETBASE_URL } from '../../../config';
import {
  exportKeyBase64,
  generatePbPassword,
  generateStealthUuid,
  generateX25519KeyPair,
} from '../utils/crypto';
import { pbIdFromLocalUuid } from '../utils/pbUserId';
import { readFromStorage, removeFromStorage, writeToStorage } from '../utils/storage';

const STORAGE_KEYS = {
  uuid: 'uuid',
  nickname: 'nickname',
  privateKey: 'private_key',
  publicKey: 'public_key',
  pbToken: 'pb_token',
  pbPassword: 'pb_password',
  registeredAt: 'registered_at',
} as const;

export interface StealthUser {
  id: string;
  uuid: string;
  nickname: string;
  pbId: string;
  publicKey: string;
}

let currentUser: StealthUser | null = null;

export async function registerUser(nickname: string): Promise<StealthUser> {
  const uuid = generateStealthUuid();
  const keyPair = await generateX25519KeyPair();
  const publicKeyB64 = await exportKeyBase64(keyPair.publicKey);
  const privateKeyB64 = await exportKeyBase64(keyPair.privateKey);
  const pbId = await pbIdFromLocalUuid(uuid);
  const pbPassword = generatePbPassword();

  const pb = new PocketBase(POCKETBASE_URL);
  const email = `${pbId}@stealth.local`;

  try {
    await pb.collection('users').authWithPassword(email, pbPassword);
  } catch {
    await pb.collection('users').create({
      id: pbId,
      email,
      password: pbPassword,
      passwordConfirm: pbPassword,
      name: nickname,
    });
    await pb.collection('users').authWithPassword(email, pbPassword);
  }

  const actualPbId = pb.authStore.record?.id;
  if (actualPbId !== pbId) {
    throw new Error(`Auth id mismatch: expected=${pbId}, got=${actualPbId}`);
  }

  writeToStorage(STORAGE_KEYS.uuid, uuid);
  writeToStorage(STORAGE_KEYS.nickname, nickname);
  writeToStorage(STORAGE_KEYS.privateKey, privateKeyB64);
  writeToStorage(STORAGE_KEYS.publicKey, publicKeyB64);
  writeToStorage(STORAGE_KEYS.pbToken, pb.authStore.token);
  writeToStorage(STORAGE_KEYS.pbPassword, pbPassword);
  writeToStorage(STORAGE_KEYS.registeredAt, new Date().toISOString());

  currentUser = {
    id: pbId,
    uuid,
    nickname,
    pbId,
    publicKey: publicKeyB64,
  };

  return currentUser;
}

export async function loginFromStorage(): Promise<StealthUser | null> {
  const uuid = readFromStorage(STORAGE_KEYS.uuid);
  const nickname = readFromStorage(STORAGE_KEYS.nickname);
  const privateKey = readFromStorage(STORAGE_KEYS.privateKey);
  const publicKey = readFromStorage(STORAGE_KEYS.publicKey);
  const pbToken = readFromStorage(STORAGE_KEYS.pbToken);

  if (!uuid || !nickname || !privateKey || !publicKey) {
    return null;
  }

  const pbId = await pbIdFromLocalUuid(uuid);

  if (pbToken) {
    const pb = new PocketBase(POCKETBASE_URL);
    pb.authStore.save(pbToken, { id: pbId, collectionId: 'users', collectionName: 'users' } as any);

    try {
      await pb.collection('users').authRefresh();
    } catch {
      pb.authStore.clear();
      removeFromStorage(STORAGE_KEYS.pbToken);
      return null;
    }

    const actualPbId = pb.authStore.record?.id;
    if (actualPbId !== pbId) {
      pb.authStore.clear();
      removeFromStorage(STORAGE_KEYS.pbToken);
      return null;
    }
  }

  currentUser = {
    id: pbId,
    uuid,
    nickname,
    pbId,
    publicKey,
  };

  return currentUser;
}

export function getCurrentUser(): StealthUser | null {
  return currentUser;
}

export async function logout(): Promise<void> {
  currentUser = null;
  for (const key of Object.values(STORAGE_KEYS)) {
    removeFromStorage(key);
  }
}

export function isRegistered(): boolean {
  return Boolean(readFromStorage(STORAGE_KEYS.uuid));
}
