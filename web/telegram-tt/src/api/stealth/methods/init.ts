import PocketBase from 'pocketbase';
import type {
  ApiInitialArgs,
  ApiOnProgress,
  OnApiUpdate,
} from '../../types';
import type { LocalDb } from '../../gramjs/localDb';
import type { MethodArgs, MethodResponse, Methods } from '../../gramjs/methods/types';
import { POCKETBASE_URL } from '../../../config';

let pb: PocketBase;
let onUpdate: OnApiUpdate;

export async function initApi(_onUpdate: OnApiUpdate, _initialArgs: ApiInitialArgs, _initialLocalDb?: LocalDb) {
  onUpdate = _onUpdate;

  pb = new PocketBase(POCKETBASE_URL);

  if (pb.authStore.isValid) {
    try {
      await pb.collection('users').authRefresh();
    } catch {
      pb.authStore.clear();
    }
  }

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
}

export async function callApi<T extends keyof Methods>(fnName: T, ...args: MethodArgs<T>): Promise<MethodResponse<T>> {
  throw new Error(`Stealth API: ${fnName} not implemented`);
}

export function cancelApiProgress(progressCallback: ApiOnProgress) {
  progressCallback.isCanceled = true;
}
