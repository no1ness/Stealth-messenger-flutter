import type PocketBase from 'pocketbase';

import type { OnApiUpdate } from '../../types';
import type { StealthMessage } from '../types';

import { buildApiMessage } from '../apiBuilders/buildApiMessage';
import { localDb as stealthDb } from '../localDb';
import { getCurrentUser } from './auth';
import { addMessageToChat } from './chats';

const MESSAGES_COLLECTION = 'stealth_messages';

let pb: PocketBase;
let onUpdate: OnApiUpdate;
let messagesUnsubscribe: (() => void) | undefined;

export function initSignaling(pocketBase: PocketBase, updateCallback: OnApiUpdate) {
  pb = pocketBase;
  onUpdate = updateCallback;
}

const RETRY_QUEUE: Array<{ msg: StealthMessage; attempt: number }> = [];
let retryTimer: ReturnType<typeof setTimeout> | undefined;

function scheduleRetry(): void {
  if (retryTimer || RETRY_QUEUE.length === 0) return;
  const delay = Math.min(1000 * 2 ** RETRY_QUEUE[0].attempt, 30000);
  retryTimer = setTimeout(async () => {
    retryTimer = undefined;
    const item = RETRY_QUEUE.shift();
    if (!item) return;
    const ok = await sendMessageP2P(item.msg, []);
    if (!ok && item.attempt < 5) {
      RETRY_QUEUE.push({ msg: item.msg, attempt: item.attempt + 1 });
    }
    scheduleRetry();
  }, delay);
}

export async function sendMessageP2P(msg: StealthMessage, _chatMemberIds: string[]): Promise<boolean> {
  try {
    const payload = {
      chatId: msg.chatId,
      senderId: msg.senderId,
      encryptedContent: msg.content,
      messageId: msg.id,
      createdAt: new Date(msg.createdAt).toISOString(),
      replyToId: msg.replyToId || undefined,
    };

    await pb.collection(MESSAGES_COLLECTION).create(payload);
    return true;
  } catch {
    RETRY_QUEUE.push({ msg, attempt: 0 });
    scheduleRetry();
    return false;
  }
}

export function subscribeToMessages(): void {
  if (messagesUnsubscribe) return;

  const handleRecord = (record: any) => {
    const data = record as unknown as {
      id: string;
      chatId: string;
      senderId: string;
      encryptedContent: string;
      messageId: number;
      createdAt: string;
      replyToId?: number;
    };

    if (data.senderId === getLocalUserId()) return;

    const localUserId = getLocalUserId();
    if (!localUserId) return;

    if (!stealthDb.chats[data.chatId]) {
      stealthDb.chats[data.chatId] = {
        id: data.chatId,
        title: data.senderId,
        isPrivate: true,
        memberIds: [data.senderId, localUserId],
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
    }

    const chatMemberIds = stealthDb.chats[data.chatId]?.memberIds;
    if (!chatMemberIds?.includes(localUserId)) return;

    const stealthMsg: StealthMessage = {
      id: data.messageId,
      chatId: data.chatId,
      senderId: data.senderId,
      content: data.encryptedContent,
      type: 'message',
      createdAt: new Date(data.createdAt).getTime(),
      replyToId: data.replyToId,
      deliveryStatus: 'delivered',
    };

    addMessageToChat(data.chatId, stealthMsg);

    if (onUpdate) {
      onUpdate({
        '@type': 'newMessage',
        id: stealthMsg.id,
        chatId: data.chatId,
        message: buildApiMessage(stealthMsg),
      });
    }
  };

  pb.collection(MESSAGES_COLLECTION).subscribe('*', (e) => {
    if (e.action === 'create') {
      handleRecord(e.record);
    }
  }).then((unsub) => {
    messagesUnsubscribe = unsub;
  });
}

export async function fetchPublicKey(userId: string): Promise<string | undefined> {
  try {
    const record = await pb.collection('user_profiles').getFirstListItem(`userId="${userId}"`);
    return (record as unknown as { publicKey?: string }).publicKey;
  } catch {
    return undefined;
  }
}

export async function storePublicKey(userId: string, publicKeyB64: string): Promise<void> {
  try {
    const record = await pb.collection('user_profiles').getFirstListItem(`userId="${userId}"`);
    await pb.collection('user_profiles').update(record.id, { publicKey: publicKeyB64 });
  } catch {
    // profile not found
  }
}

export function unsubscribeFromMessages(): void {
  if (messagesUnsubscribe) {
    messagesUnsubscribe();
    messagesUnsubscribe = undefined;
  }
}

function getLocalUserId(): string {
  return getCurrentUser()?.pbId || '';
}
