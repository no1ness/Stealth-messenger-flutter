import { TEST_API_URL } from "../config.mjs";

export class EventBus {
  constructor(baseUrl = TEST_API_URL) {
    this._base = baseUrl;
    this._seen = new Set();
  }

  async waitForEvent(type, { timeoutMs = 15000, pollMs = 200 } = {}) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const event = await this._pollOnce(type);
      if (event) return event;
      await _sleep(pollMs);
    }
    throw new Error(`waitForEvent("${type}") timed out after ${timeoutMs}ms`);
  }

  async _pollOnce(type) {
    try {
      const res = await fetch(`${this._base}/events`, { signal: AbortSignal.timeout(3000) });
      if (!res.ok) return null;
      const list = await res.json();
      for (const ev of list) {
        const key = ev.type + ":" + (ev.chatId || ev.roomId || ev.userId || "");
        if (ev.type === type && !this._seen.has(key)) {
          this._seen.add(key);
          return ev;
        }
      }
    } catch {
      // server not ready yet
    }
    return null;
  }
}

function _sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}
