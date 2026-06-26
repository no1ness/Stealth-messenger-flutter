import type { ApiUser } from '../../types';
import type { StealthUserProfile } from '../types';

export function buildApiUser(profile: StealthUserProfile, isSelf = false): ApiUser {
  return {
    id: profile.userId,
    isMin: false,
    isSelf: isSelf ? true as const : undefined,
    type: 'userTypeRegular',
    firstName: profile.nickname || profile.userId.slice(0, 8),
    phoneNumber: profile.userId,
    accessHash: profile.publicKey ? profile.publicKey.slice(0, 16) : undefined,
  };
}
