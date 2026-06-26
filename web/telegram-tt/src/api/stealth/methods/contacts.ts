import PocketBase from 'pocketbase';

import type { ApiUser, OnApiUpdate } from '../../types';

import { POCKETBASE_URL } from '../../../config';
import { buildApiUser } from '../apiBuilders/buildApiUser';
import { buildApiUserStatus } from '../apiBuilders/buildApiUserStatus';
import { localDb as stealthDb } from '../localDb';

let pb: PocketBase;
let onUpdate: OnApiUpdate;

export function initContacts(pocketBase: PocketBase, updateCallback: OnApiUpdate) {
  pb = pocketBase;
  onUpdate = updateCallback;
}

function notifyUserStatus(userId: string, isOnline?: boolean, lastSeen?: number) {
  if (!onUpdate) return;
  onUpdate({
    '@type': 'updateUserStatus',
    userId,
    status: buildApiUserStatus(isOnline, lastSeen),
  });
}

export async function fetchContactList(): Promise<{
  users: ApiUser[];
  userStatusesById: Record<string, ReturnType<typeof buildApiUserStatus>>;
} | undefined> {
  if (!pb) pb = new PocketBase(POCKETBASE_URL);

  try {
    const records = await pb.collection('user_profiles').getFullList({
      sort: '-lastSeen',
    });

    const users: ApiUser[] = [];
    const userStatusesById: Record<string, ReturnType<typeof buildApiUserStatus>> = {};

    for (const record of records) {
      const profile = record as unknown as {
        userId: string;
        publicKey?: string;
        isOnline?: boolean;
        lastSeen?: string;
        nickname?: string;
      };

      stealthDb.users[profile.userId] = {
        userId: profile.userId,
        publicKey: profile.publicKey,
        isOnline: profile.isOnline,
        lastSeen: profile.lastSeen ? Math.floor(new Date(profile.lastSeen).getTime() / 1000) : undefined,
        nickname: profile.nickname,
      };

      const user = buildApiUser(stealthDb.users[profile.userId]);
      users.push(user);
      userStatusesById[profile.userId] = buildApiUserStatus(profile.isOnline, stealthDb.users[profile.userId].lastSeen);
    }

    return { users, userStatusesById };
  } catch {
    return undefined;
  }
}

export async function fetchUsers({ users: userQueries }: { users: ApiUser[] }): Promise<{
  users: ApiUser[];
  userStatusesById: Record<string, ReturnType<typeof buildApiUserStatus>>;
} | undefined> {
  if (!pb) pb = new PocketBase(POCKETBASE_URL);

  const result: ApiUser[] = [];
  const userStatusesById: Record<string, ReturnType<typeof buildApiUserStatus>> = {};

  for (const query of userQueries) {
    const existing = stealthDb.users[query.id];
    if (existing) {
      result.push(buildApiUser(existing));
      userStatusesById[query.id] = buildApiUserStatus(existing.isOnline, existing.lastSeen);
      continue;
    }

    try {
      const record = await pb.collection('user_profiles').getFirstListItem(`userId="${query.id}"`);
      const profile = record as unknown as {
        userId: string;
        publicKey?: string;
        isOnline?: boolean;
        lastSeen?: string;
        nickname?: string;
      };

      stealthDb.users[query.id] = {
        userId: profile.userId,
        publicKey: profile.publicKey,
        isOnline: profile.isOnline,
        lastSeen: profile.lastSeen ? Math.floor(new Date(profile.lastSeen).getTime() / 1000) : undefined,
        nickname: profile.nickname,
      };

      result.push(buildApiUser(stealthDb.users[query.id]));
      userStatusesById[query.id] = buildApiUserStatus(profile.isOnline, stealthDb.users[query.id].lastSeen);
    } catch {
      result.push(buildApiUser({ userId: query.id, nickname: query.firstName }));
      userStatusesById[query.id] = buildApiUserStatus(false, undefined);
    }
  }

  return { users: result, userStatusesById };
}

export async function importContact({
  userId,
  firstName,
}: {
  userId?: string;
  firstName?: string;
}): Promise<string | undefined> {
  if (!userId || !firstName) return undefined;
  stealthDb.users[userId] = stealthDb.users[userId] || { userId, nickname: firstName };
  return userId;
}

export async function deleteContact({ id }: { id: string }): Promise<void> {
  delete stealthDb.users[id];
}

let presenceUnsubscribe: (() => void) | null = null;

export function subscribeToPresence() {
  if (!pb) return;

  pb.collection('user_profiles').subscribe('*', (e) => {
    const record = e.record as unknown as {
      userId: string;
      isOnline?: boolean;
      lastSeen?: string;
    };

    if (!record.userId) return;
    const lastSeen = record.lastSeen
      ? Math.floor(new Date(record.lastSeen).getTime() / 1000) : undefined;
    notifyUserStatus(record.userId, record.isOnline, lastSeen);
  }).then((unsub) => {
    presenceUnsubscribe = unsub;
  });
}

export function unsubscribeFromPresence() {
  presenceUnsubscribe?.();
  presenceUnsubscribe = null;
}

export async function searchContacts(query: string): Promise<{
  users: ApiUser[];
  userStatusesById: Record<string, ReturnType<typeof buildApiUserStatus>>;
} | undefined> {
  if (!pb) pb = new PocketBase(POCKETBASE_URL);

  try {
    const records = await pb.collection('user_profiles').getList(1, 50, {
      filter: `nickname ~ "${query}"`,
      sort: '-lastSeen',
    });

    const users: ApiUser[] = [];
    const userStatusesById: Record<string, ReturnType<typeof buildApiUserStatus>> = {};

    for (const record of records.items) {
      const profile = record as unknown as {
        userId: string;
        publicKey?: string;
        isOnline?: boolean;
        lastSeen?: string;
        nickname?: string;
      };

      stealthDb.users[profile.userId] = {
        userId: profile.userId,
        publicKey: profile.publicKey,
        isOnline: profile.isOnline,
        lastSeen: profile.lastSeen ? Math.floor(new Date(profile.lastSeen).getTime() / 1000) : undefined,
        nickname: profile.nickname,
      };

      users.push(buildApiUser(stealthDb.users[profile.userId]));
      userStatusesById[profile.userId] = buildApiUserStatus(profile.isOnline, stealthDb.users[profile.userId].lastSeen);
    }

    return { users, userStatusesById };
  } catch {
    return { users: [], userStatusesById: {} };
  }
}
