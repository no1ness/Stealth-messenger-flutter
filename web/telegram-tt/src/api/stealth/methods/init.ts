import PocketBase from 'pocketbase';

import type { LocalDb } from '../../gramjs/localDb';
import type { MethodArgs, MethodResponse, Methods } from '../../gramjs/methods/types';
import type {
  ApiInitialArgs,
  ApiOnProgress,
  ApiUpdateAuthorizationStateType,
  OnApiUpdate,
} from '../../types';

import { POCKETBASE_URL } from '../../../config';
import { readFromStorage } from '../utils/storage';
import { getCurrentUser, loginFromStorage, registerUser } from './auth';
import { createGroupChat, ensureChatsLoaded, fetchChat, fetchChats, fetchFullChat, searchChats } from './chats';
import {
  deleteContact, fetchContactList, fetchUsers, importContact, initContacts, subscribeToPresence,
  unsubscribeFromPresence,
} from './contacts';
import {
  deleteMessages, editMessage, fetchMessage, fetchMessages, fetchMessagesById, forwardMessages,
  initMessages, markMessageListRead, markMessagesRead, pinMessage, sendMessage, sendMessageAction,
  sendMessageLocal, unpinAllMessages,
} from './messages';
import { initSignaling, subscribeToMessages } from './signaling';

let pb: PocketBase;
let onUpdate: OnApiUpdate;

function emitAuthState(state: ApiUpdateAuthorizationStateType) {
  onUpdate({
    '@type': 'updateAuthorizationState',
    authorizationState: state,
  });
}

export async function initApi(_onUpdate: OnApiUpdate, _initialArgs: ApiInitialArgs, _initialLocalDb?: LocalDb) {
  onUpdate = _onUpdate;

  pb = new PocketBase(POCKETBASE_URL);

  const user = getCurrentUser() || await loginFromStorage();
  if (user) {
    const token = readFromStorage('pb_token');
    if (token) {
      pb.authStore.save(
        token,
        { id: user.pbId, collectionId: 'users', collectionName: 'users' } as any,
      );
    }
  }

  initContacts(pb, onUpdate);
  initMessages(onUpdate);
  initSignaling(pb, onUpdate);
  ensureChatsLoaded();

  pb.authStore.onChange((_token) => {
    onUpdate({
      '@type': 'updateConnectionState',
      connectionState: pb.authStore.isValid ? 'connectionStateReady' : 'connectionStateConnecting',
    });
  });

  onUpdate({
    '@type': 'updateConnectionState',
    connectionState: pb.authStore.isValid ? 'connectionStateReady' : 'connectionStateConnecting',
  });

  if (user) {
    subscribeToPresence();
    subscribeToMessages();
  }

  emitAuthState(user ? 'authorizationStateReady' : 'authorizationStateWaitPhoneNumber');
}

export async function callApi<T extends keyof Methods>(fnName: T, ...args: MethodArgs<T>): Promise<MethodResponse<T>> {
  switch (fnName) {
    case 'provideAuthPhoneNumber': {
      const [nickname] = args as unknown as [string];
      try {
        await registerUser(nickname);
        emitAuthState('authorizationStateReady');
      } catch {
        // TODO: emit error
      }
      return undefined as MethodResponse<T>;
    }
    case 'destroy': {
      const { logout } = await import('./auth');
      unsubscribeFromPresence();
      await logout();
      emitAuthState('authorizationStateWaitPhoneNumber');
      return undefined as MethodResponse<T>;
    }
    case 'fetchContactList': {
      const result = await fetchContactList();
      return result as MethodResponse<T>;
    }
    case 'fetchUsers': {
      const [params] = args as unknown as [{ users: import('../../types').ApiUser[] }];
      const result = await fetchUsers(params);
      return result as MethodResponse<T>;
    }
    case 'importContact': {
      const [params] = args as unknown as [{ phone?: string; firstName?: string; lastName?: string }];
      const result = await importContact({ userId: params.phone, firstName: params.firstName });
      return result as MethodResponse<T>;
    }
    case 'deleteContact': {
      const [params] = args as unknown as [{ id: string }];
      await deleteContact(params);
      return undefined as MethodResponse<T>;
    }
    case 'fetchChats': {
      const [params] = args as unknown as [Record<string, unknown> | undefined];
      const result = await fetchChats(params);
      return result as MethodResponse<T>;
    }
    case 'fetchFullChat': {
      const [chat] = args as unknown as [import('../../types').ApiChat];
      const result = await fetchFullChat(chat);
      return result as MethodResponse<T>;
    }
    case 'createGroupChat': {
      const [params] = args as unknown as [{ title: string; users: import('../../types').ApiUser[] }];
      const result = await createGroupChat(params);
      return result as MethodResponse<T>;
    }
    case 'searchChats': {
      const [params] = args as unknown as [{ query: string }];
      const result = await searchChats(params);
      return result as MethodResponse<T>;
    }
    case 'fetchChat': {
      const [params] = args as unknown as [{ type: 'user' | 'self' | 'support'; user?: import('../../types').ApiUser }];
      const result = await fetchChat(params);
      return result as MethodResponse<T>;
    }
    case 'sendMessage': {
      const [params, progressCb] = args as unknown as [any, any];
      const result = await sendMessage(params, progressCb);
      return result as MethodResponse<T>;
    }
    case 'sendMessageLocal': {
      const [params] = args as unknown as [any];
      const result = sendMessageLocal(params);
      return result as MethodResponse<T>;
    }
    case 'editMessage': {
      type EditMsgParams = {
        chat: import('../../types').ApiChat;
        message: import('../../types').ApiMessage;
        text: string;
      };
      const [params] = args as unknown as [EditMsgParams];
      const result = await editMessage(params);
      return result as MethodResponse<T>;
    }
    case 'deleteMessages': {
      type DelMsgParams = { chat: import('../../types').ApiChat; messageIds: number[] };
      const [params] = args as unknown as [DelMsgParams];
      await deleteMessages(params);
      return undefined as MethodResponse<T>;
    }
    case 'fetchMessages': {
      type FetchMsgsParams = { chat: import('../../types').ApiChat; limit: number; offsetId?: number };
      const [params] = args as unknown as [FetchMsgsParams];
      const result = await fetchMessages(params);
      return result as MethodResponse<T>;
    }
    case 'fetchMessagesById': {
      type FetchMsgsByIdParams = { chat: import('../../types').ApiChat; messageIds: number[] };
      const [params] = args as unknown as [FetchMsgsByIdParams];
      const result = await fetchMessagesById(params);
      return result as MethodResponse<T>;
    }
    case 'fetchMessage': {
      type FetchMsgParams = { chat: import('../../types').ApiChat; messageId: number };
      const [params] = args as unknown as [FetchMsgParams];
      const result = await fetchMessage(params);
      return result as MethodResponse<T>;
    }
    case 'sendMessageAction': {
      type SendActionParams = { peer: { id: string }; threadId?: number; action: string };
      const [params] = args as unknown as [SendActionParams];
      await sendMessageAction(params);
      return undefined as MethodResponse<T>;
    }
    case 'markMessagesRead': {
      type MarkReadParams = { chat: import('../../types').ApiChat; messageIds: number[] };
      const [params] = args as unknown as [MarkReadParams];
      await markMessagesRead(params);
      return undefined as MethodResponse<T>;
    }
    case 'markMessageListRead': {
      type MarkListParams = { chat: import('../../types').ApiChat; threadId?: number; maxId?: number };
      const [params] = args as unknown as [MarkListParams];
      await markMessageListRead(params);
      return undefined as MethodResponse<T>;
    }
    case 'pinMessage': {
      type PinMsgParams = { chat: import('../../types').ApiChat; messageId: number; isUnpin: boolean };
      const [params] = args as unknown as [PinMsgParams];
      await pinMessage(params);
      return undefined as MethodResponse<T>;
    }
    case 'unpinAllMessages': {
      type UnpinAllParams = { chat: import('../../types').ApiChat; threadId?: number };
      const [params] = args as unknown as [UnpinAllParams];
      await unpinAllMessages(params);
      return undefined as MethodResponse<T>;
    }
    case 'forwardMessages': {
      const [params] = args as unknown as [any];
      await forwardMessages(params);
      return undefined as MethodResponse<T>;
    }
    case 'fetchCurrentUser': {
      const result = getCurrentUser();
      return result as MethodResponse<T>;
    }
    case 'fetchWebPagePreview': {
      return undefined as MethodResponse<T>;
    }
    case 'fetchWebPage': {
      return undefined as MethodResponse<T>;
    }
    default:
      return undefined as MethodResponse<T>;
  }
}

export function cancelApiProgress(progressCallback: ApiOnProgress) {
  progressCallback.isCanceled = true;
}
