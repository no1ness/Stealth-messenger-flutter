import type { ApiUserStatus } from '../../types';

export function buildApiUserStatus(isOnline?: boolean, lastSeen?: number): ApiUserStatus {
  if (isOnline) {
    return { type: 'userStatusOnline', expires: lastSeen ?? Math.floor(Date.now() / 1000) + 60 };
  }
  if (lastSeen && lastSeen > 0) {
    return { type: 'userStatusOffline', wasOnline: lastSeen };
  }
  return { type: 'userStatusEmpty' };
}
