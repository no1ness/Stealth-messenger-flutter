import type { ApiChat, ApiChatFullInfo, ApiMessage, ApiUser, ApiUserStatus } from '../../types';
import type { StealthChat, StealthMessage } from '../types';

import { buildApiChat } from '../apiBuilders/buildApiChat';
import { buildApiMessage } from '../apiBuilders/buildApiMessage';
import { localDb as stealthDb } from '../localDb';

const CHATS_STORAGE_KEY = 'st_chats';
const MESSAGES_STORAGE_KEY_PREFIX = 'st_messages_';

function saveChats(): void {
  try {
    const data = JSON.stringify(Object.values(stealthDb.chats));
    localStorage.setItem(CHATS_STORAGE_KEY, data);
  } catch {
    // storage quota
  }
}

function loadChatsFromStorage(): void {
  try {
    const raw = localStorage.getItem(CHATS_STORAGE_KEY);
    if (raw) {
      const chats: StealthChat[] = JSON.parse(raw);
      for (const chat of chats) {
        stealthDb.chats[chat.id] = chat;
      }
    }
  } catch {
    // ignore
  }
}

function saveMessages(chatId: string): void {
  try {
    const msgs = stealthDb.messages[chatId];
    if (msgs) {
      localStorage.setItem(MESSAGES_STORAGE_KEY_PREFIX + chatId, JSON.stringify(msgs));
    }
  } catch {
    // storage quota
  }
}

export function ensureChatsLoaded(): void {
  if (Object.keys(stealthDb.chats).length === 0) {
    loadChatsFromStorage();
  }
}

export function generateChatId(): string {
  return crypto.randomUUID();
}

export async function fetchChats(_params?: {
  limit?: number;
  offsetDate?: number;
  offsetId?: number;
  offsetPeer?: { id: string };
  archived?: boolean;
  withPinned?: boolean;
  lastLocalServiceMessageId?: number;
}): Promise<{
  chatIds: string[];
  chats: ApiChat[];
  users: ApiUser[];
  userStatusesById: Record<string, ApiUserStatus>;
  draftsById: Record<string, unknown>;
  messages: ApiMessage[];
  orderedPinnedIds: string[] | undefined;
  totalChatCount: number;
  nextOffsetId?: number;
  lastMessageByChatId?: Record<string, number>;
} | undefined> {
  ensureChatsLoaded();

  const chatIds = Object.keys(stealthDb.chats);
  const apiChats = chatIds.map((id) => {
    const stealthChat = stealthDb.chats[id];
    if (!stealthChat) return undefined;
    return buildApiChat(stealthChat);
  }).filter(Boolean) as ApiChat[];

  const messages: ApiMessage[] = [];
  const lastMessageByChatId: Record<string, number> = {};
  for (const chatId of chatIds) {
    const msgs = stealthDb.messages[chatId];
    if (msgs && msgs.length > 0) {
      const lastMsg = msgs[msgs.length - 1];
      const apiMsg = buildApiMessage(lastMsg);
      messages.push(apiMsg);
      lastMessageByChatId[chatId] = apiMsg.id;
    }
  }

  apiChats.sort((a, b) => {
    const aMsg = messages.find((m) => m.chatId === a.id);
    const bMsg = messages.find((m) => m.chatId === b.id);
    return (bMsg?.date ?? 0) - (aMsg?.date ?? 0);
  });

  return {
    chatIds: apiChats.map((c) => c.id),
    chats: apiChats,
    users: [],
    userStatusesById: {},
    draftsById: {},
    messages,
    orderedPinnedIds: undefined,
    totalChatCount: apiChats.length,
    lastMessageByChatId,
  };
}

export async function fetchFullChat(chat: ApiChat): Promise<{
  fullInfo: ApiChatFullInfo;
  chats: ApiChat[];
  userStatusesById: Record<string, ApiUserStatus>;
} | undefined> {
  return {
    fullInfo: {},
    chats: [buildApiChat(stealthDb.chats[chat.id] || {
      id: chat.id,
      title: chat.title,
      isPrivate: chat.type === 'chatTypePrivate',
      memberIds: [],
      createdAt: Date.now(),
      updatedAt: Date.now(),
    })],
    userStatusesById: {},
  };
}

export async function createGroupChat({
  title,
  users,
}: {
  title: string;
  users: ApiUser[];
}): Promise<{ chat: ApiChat } | undefined> {
  const chatId = generateChatId();
  const memberIds = users.map((u) => u.id);

  const stealthChat: StealthChat = {
    id: chatId,
    title,
    isPrivate: memberIds.length <= 1,
    memberIds,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };

  stealthDb.chats[chatId] = stealthChat;
  saveChats();

  return { chat: buildApiChat(stealthChat) };
}

export async function fetchChat({
  type,
  user,
}: {
  type: 'user' | 'self' | 'support';
  user?: ApiUser;
}): Promise<{ chatId: string } | undefined> {
  if (type === 'self') {
    return { chatId: 'self' };
  }
  if (user) {
    return { chatId: user.id };
  }
  return undefined;
}

export async function searchChats({ query }: { query: string }): Promise<{
  accountResultIds: string[];
  globalResultIds: string[];
} | undefined> {
  ensureChatsLoaded();
  const lower = query.toLowerCase();
  const ids = Object.values(stealthDb.chats)
    .filter((c) => c.title.toLowerCase().includes(lower))
    .map((c) => c.id);

  return {
    accountResultIds: ids,
    globalResultIds: [],
  };
}

export function addMessageToChat(chatId: string, msg: StealthMessage): void {
  if (!stealthDb.messages[chatId]) {
    stealthDb.messages[chatId] = [];
  }
  stealthDb.messages[chatId].push(msg);
  saveMessages(chatId);

  if (stealthDb.chats[chatId]) {
    stealthDb.chats[chatId].updatedAt = Date.now();
    stealthDb.chats[chatId].lastMessageId = msg.id;
    saveChats();
  }
}
