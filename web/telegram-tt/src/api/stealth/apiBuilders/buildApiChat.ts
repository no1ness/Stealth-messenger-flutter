import type { ApiChat } from '../../types';
import type { StealthChat } from '../types';

export function buildApiChat(chat: StealthChat): ApiChat {
  return {
    id: chat.id,
    title: chat.title,
    type: chat.isPrivate ? 'chatTypePrivate' : 'chatTypeBasicGroup',
    membersCount: chat.memberIds.length,
    creationDate: Math.floor(chat.createdAt / 1000),
    isMin: false,
    isNotJoined: false,
    isCreator: true,
  };
}
