import { TEST_SESSION } from '../../../config';

function prefix(key: string): string {
  return TEST_SESSION ? `st_${TEST_SESSION}_${key}` : `st_${key}`;
}

export function readFromStorage(key: string): string | null {
  try {
    return localStorage.getItem(prefix(key));
  } catch {
    return null;
  }
}

export function writeToStorage(key: string, value: string): void {
  try {
    localStorage.setItem(prefix(key), value);
  } catch {
    // storage quota exceeded
  }
}

export function removeFromStorage(key: string): void {
  try {
    localStorage.removeItem(prefix(key));
  } catch {
    // ignore
  }
}
