/* eslint-disable @typescript-eslint/require-await */
import type { ApiAttachment, ApiChat, ApiMessage, ApiMessageEntity, OnApiUpdate } from '../../types';
import type { StealthMessage } from '../types';

import { buildApiMessage } from '../apiBuilders/buildApiMessage';
import { localDb as stealthDb } from '../localDb';
import { getCurrentUser } from './auth';

let onUpdate: OnApiUpdate;

let localMessageIdCounter = 0;

export function initMessages(updateCallback: OnApiUpdate) {
  onUpdate = updateCallback;
}

function getNextLocalMessageId(lastMessageId = 0): number {
  localMessageIdCounter -= 1;
  return Math.min(localMessageIdCounter, lastMessageId - 1);
}

function getChatMessages(chatId: string): StealthMessage[] {
  if (!stealthDb.messages[chatId]) {
    stealthDb.messages[chatId] = [];
  }
  return stealthDb.messages[chatId];
}

function persistMessages(chatId: string): void {
  try {
    localStorage.setItem(`st_messages_${chatId}`, JSON.stringify(stealthDb.messages[chatId]));
  } catch {
    // storage quota
  }
}

function persistChats(): void {
  try {
    localStorage.setItem('st_chats', JSON.stringify(Object.values(stealthDb.chats)));
  } catch {
    // storage quota
  }
}

function getSenderId(): string {
  return getCurrentUser()?.pbId || 'self';
}

function buildStealthMessage(params: {
  chat: ApiChat;
  text?: string;
  replyToMsgId?: number;
  senderId: string;
}): StealthMessage {
  const msgs = getChatMessages(params.chat.id);
  const lastId = msgs.length > 0 ? msgs[msgs.length - 1].id : 0;
  const id = getNextLocalMessageId(lastId);

  return {
    id,
    chatId: params.chat.id,
    senderId: params.senderId,
    content: params.text || '',
    type: 'message',
    createdAt: Date.now(),
    replyToId: params.replyToMsgId,
    deliveryStatus: 'pending',
  };
}

export async function sendMessage(
  params: {
    chat?: ApiChat;
    text?: string;
    entities?: ApiMessageEntity[];
    replyInfo?: { type: string; replyToMsgId: number };
    wasDrafted?: boolean;
  },
  _onProgress?: (progress: number, messageKey: string) => void,
): Promise<ApiMessage | undefined> {
  const localMsg = sendMessageLocal(params);
  if (!localMsg) return undefined;

  const chat = params.chat!;

  const { sendMessageP2P } = await import('./signaling');
  const memberIds = stealthDb.chats[chat.id]?.memberIds || [];

  sendMessageP2P(
    {
      id: localMsg.id,
      chatId: chat.id,
      senderId: getSenderId(),
      content: params.text || '',
      type: 'message',
      createdAt: Date.now(),
      replyToId: params.replyInfo?.type === 'message' ? params.replyInfo.replyToMsgId : undefined,
      deliveryStatus: 'sent',
    },
    memberIds,
  ).then((sent) => {
    const msgs = getChatMessages(chat.id);
    const found = msgs.find((m) => m.id === localMsg.id);
    if (found) {
      found.deliveryStatus = sent ? 'sent' : 'pending';
      persistMessages(chat.id);
      if (onUpdate && !sent) {
        onUpdate({
          '@type': 'updateMessage',
          id: localMsg.id,
          chatId: chat.id,
          message: { sendingState: 'messageSendingStatePending' },
          isFull: false,
        });
      }
    }
  });

  return localMsg;
}

export function sendMessageLocal(
  params: {
    chat?: ApiChat;
    text?: string;
    entities?: ApiMessageEntity[];
    replyInfo?: { type: string; replyToMsgId: number };
    wasDrafted?: boolean;
    isPending?: true;
    attachment?: ApiAttachment;
  },
): ApiMessage | undefined {
  const chat = params.chat;
  if (!chat) return undefined;

  const replyToMsgId = params.replyInfo?.type === 'message' ? params.replyInfo.replyToMsgId : undefined;

  const stealthMsg = buildStealthMessage({
    chat,
    text: params.text,
    replyToMsgId,
    senderId: getSenderId(),
  });

  const msgs = getChatMessages(chat.id);
  msgs.push(stealthMsg);
  persistMessages(chat.id);

  if (stealthDb.chats[chat.id]) {
    stealthDb.chats[chat.id].lastMessageId = stealthMsg.id;
    stealthDb.chats[chat.id].updatedAt = Date.now();
    persistChats();
  }

  const apiMessage = buildApiMessage(stealthMsg);

  if (onUpdate) {
    onUpdate({
      '@type': 'newMessage',
      id: stealthMsg.id,
      chatId: chat.id,
      message: apiMessage,
      wasDrafted: params.wasDrafted,
    });
  }

  return apiMessage;
}

export async function editMessage({
  chat,
  message,
  text,
}: {
  chat: ApiChat;
  message: ApiMessage;
  text: string;
  entities?: ApiMessageEntity[];
  attachment?: ApiAttachment;
  noWebPage?: boolean;
}): Promise<boolean | undefined> {
  const msgs = getChatMessages(chat.id);
  const found = msgs.find((m) => m.id === message.id);
  if (!found) return undefined;

  found.content = text;
  found.editedAt = Date.now();
  persistMessages(chat.id);

  const updatedMessage = buildApiMessage(found);

  if (onUpdate) {
    onUpdate({
      '@type': 'updateMessage',
      id: message.id,
      chatId: chat.id,
      message: updatedMessage,
      isFull: true,
    });
  }

  return true;
}

export async function deleteMessages({
  chat,
  messageIds,
}: {
  chat: ApiChat;
  messageIds: number[];
  shouldDeleteForAll?: boolean;
}): Promise<void> {
  const msgs = getChatMessages(chat.id);
  for (const id of messageIds) {
    const idx = msgs.findIndex((m) => m.id === id);
    if (idx !== -1) {
      msgs.splice(idx, 1);
    }
  }
  persistMessages(chat.id);

  if (onUpdate) {
    onUpdate({
      '@type': 'deleteMessages',
      ids: messageIds,
    });
  }
}

export async function fetchMessages({
  chat,
  limit,
  offsetId,
}: {
  chat: ApiChat;
  threadId?: number;
  offsetId?: number;
  isSavedDialog?: boolean;
  addOffset?: number;
  limit: number;
}): Promise<{
  messages: ApiMessage[];
  users: never[];
  chats: never[];
  count: number;
  topics: never[];
} | undefined> {
  const msgs = getChatMessages(chat.id);

  let filtered = msgs.filter((m) => !m.isDeleted);
  if (offsetId) {
    const idx = filtered.findIndex((m) => m.id === offsetId);
    if (idx !== -1) {
      filtered = filtered.slice(0, idx);
    }
  }
  const slice = filtered.slice(-limit).reverse();

  return {
    messages: slice.map(buildApiMessage),
    users: [],
    chats: [],
    count: filtered.length,
    topics: [],
  };
}

export async function fetchMessagesById({
  chat,
  messageIds,
}: {
  chat: ApiChat;
  messageIds: number[];
}): Promise<(ApiMessage | undefined)[] | undefined> {
  const msgs = getChatMessages(chat.id);
  return messageIds.map((id) => {
    const found = msgs.find((m) => m.id === id);
    return found ? buildApiMessage(found) : undefined;
  });
}

export async function fetchMessage({
  chat,
  messageId,
}: {
  chat: ApiChat;
  messageId: number;
}): Promise<{ messages: ApiMessage[] } | undefined> {
  const msgs = getChatMessages(chat.id);
  const found = msgs.find((m) => m.id === messageId && !m.isDeleted);
  if (!found) return undefined;

  return { messages: [buildApiMessage(found)] };
}

export async function sendMessageAction(_params: {
  peer: { id: string };
  threadId?: number;
  action: string;
}): Promise<undefined> {
  return undefined;
}

export async function markMessagesRead(_params: {
  chat: ApiChat;
  messageIds: number[];
}): Promise<void> {
  // handled locally
}

export async function markMessageListRead(_params: {
  chat: ApiChat;
  threadId?: number;
  maxId?: number;
}): Promise<void> {
}

export async function pinMessage({
  chat,
  messageId,
  isUnpin,
}: {
  chat: ApiChat;
  messageId: number;
  isUnpin: boolean;
  isOneSide?: boolean;
  isSilent?: boolean;
}): Promise<void> {
  const msgs = getChatMessages(chat.id);
  const found = msgs.find((m) => m.id === messageId);
  if (!found) return;

  const apiMsg = buildApiMessage(found);

  if (onUpdate) {
    onUpdate({
      '@type': 'updateMessage',
      id: messageId,
      chatId: chat.id,
      message: { ...apiMsg, isPinned: !isUnpin },
      isFull: false,
    });
  }
}

export async function unpinAllMessages({
  chat,
}: {
  chat: ApiChat;
  threadId?: number;
}): Promise<void> {
  // no pinned messages in local storage
}

export async function forwardMessages(_params: {
  fromChat: ApiChat;
  toChat: ApiChat;
  messages: ApiMessage[];
  isSilent?: boolean;
  scheduledAt?: number;
  sendAs?: { id: string };
  wasDrafted?: boolean;
}): Promise<void> {
  for (const msg of _params.messages) {
    sendMessageLocal({
      chat: _params.toChat,
      text: msg.content.text?.text,
      replyInfo: msg.replyInfo?.type === 'message' && msg.replyInfo.replyToMsgId
        ? { type: 'message' as const, replyToMsgId: msg.replyInfo.replyToMsgId }
        : undefined,
      wasDrafted: _params.wasDrafted,
    });
  }
}
