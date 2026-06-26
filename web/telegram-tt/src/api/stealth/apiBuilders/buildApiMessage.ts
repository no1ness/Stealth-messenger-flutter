import type { ApiMessage } from '../../types';
import type { StealthMessage } from '../types';

import { buildApiFormattedText } from './buildApiFormattedText';

export function buildApiMessage(msg: StealthMessage): ApiMessage {
  const isOutgoing = msg.deliveryStatus !== undefined;

  return {
    id: msg.id,
    chatId: msg.chatId,
    date: Math.floor(msg.createdAt / 1000),
    content: {
      text: buildApiFormattedText(msg.content),
    },
    isOutgoing,
    senderId: msg.senderId,
    sendingState: msg.deliveryStatus === 'pending' ? 'messageSendingStatePending' as const : undefined,
    replyInfo: msg.replyToId !== undefined ? {
      type: 'message' as const,
      replyToMsgId: msg.replyToId,
    } : undefined,
    isEdited: msg.editedAt !== undefined ? true as const : undefined,
    editDate: msg.editedAt !== undefined ? Math.floor(msg.editedAt / 1000) : undefined,
  };
}
