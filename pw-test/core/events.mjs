export class EventBus {
  constructor() {
    this._queue = [];
    this._waiters = [];
    this._seen = new Set();
  }

  push(event) {
    const key =
      event.type +
      ":" +
      (event.chatId || event.roomId || event.userId || event.text || "");
    if (this._seen.has(key)) return;
    this._seen.add(key);

    this._queue.push(event);

    const matching = this._waiters.filter((w) => w.type === event.type);
    for (const w of matching) {
      w.resolve(event);
    }
    this._waiters = this._waiters.filter((w) => w.type !== event.type);
  }

  async waitForEvent(type, { timeoutMs = 15000 } = {}) {
    const existing = this._queue.find((e) => e.type === type);
    if (existing) return existing;

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this._waiters = this._waiters.filter((w) => w.resolve !== resolve);
        reject(
          new Error(`waitForEvent("${type}") timed out after ${timeoutMs}ms`),
        );
      }, timeoutMs);
      this._waiters.push({
        type,
        resolve: (ev) => {
          clearTimeout(timer);
          resolve(ev);
        },
      });
    });
  }
}
