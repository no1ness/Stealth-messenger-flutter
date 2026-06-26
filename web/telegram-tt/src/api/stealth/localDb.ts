import type { StealthChat, StealthMessage, StealthUserProfile } from './types';

class StealthLocalDb {
  users: Record<string, StealthUserProfile> = {};
  chats: Record<string, StealthChat> = {};
  messages: Record<string, StealthMessage[]> = {};
}

export const localDb = new StealthLocalDb();

export function clearLocalDb(): void {
  localDb.users = {};
  localDb.chats = {};
  localDb.messages = {};
}
