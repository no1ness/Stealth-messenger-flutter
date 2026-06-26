export interface StealthUserProfile {
  userId: string;
  publicKey?: string;
  isOnline?: boolean;
  lastSeen?: number;
  nickname?: string;
}

export interface StealthChat {
  id: string;
  title: string;
  isPrivate: boolean;
  memberIds: string[];
  createdAt: number;
  updatedAt: number;
  lastMessageId?: number;
  unreadCount?: number;
  lastMessageCreatedAt?: number;
}

export interface StealthMessage {
  id: number;
  chatId: string;
  senderId: string;
  content: string;
  type: string;
  createdAt: number;
  replyToId?: number;
  deliveryStatus?: 'pending' | 'sent' | 'delivered';
  editedAt?: number;
  isDeleted?: boolean;
}
