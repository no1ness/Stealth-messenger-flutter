import { chromium } from "playwright";
import { WEB_URL, LAUNCH_ARGS, VIEWPORT, CONTEXT_PERMISSIONS } from "../config.mjs";
import { EventBus } from "./events.mjs";
import { attachBridge } from "./bridge.mjs";
import { enableFlutterA11y } from "./flutter-helpers.mjs";

export class Client {
  constructor(name) {
    this.name = name;
    this._browser = null;
    this._page = null;
    this._events = new EventBus();
  }

  get page() {
    return this._page;
  }

  get events() {
    return this._events;
  }

  async launch() {
    this._browser = await chromium.launch({ args: LAUNCH_ARGS });
    const ctx = await this._browser.newContext({
      viewport: VIEWPORT,
      permissions: CONTEXT_PERMISSIONS,
      locale: "en-US",
    });
    this._page = await ctx.newPage();
    await attachBridge(this._page, this._events);
    await this._page.goto(WEB_URL, { waitUntil: "commit", timeout: 30000 });
  }

  async waitForSelector(selector, { timeout = 15000 } = {}) {
    await this._page.waitForSelector(selector, { timeout });
  }

  async waitForRole(role, { timeout = 15000 } = {}) {
    await this._page.waitForSelector(`[role="${role}"]`, { timeout });
  }

  async type(selector, text) {
    await this._page.fill(selector, text);
  }

  async click(selector) {
    await this._page.click(selector);
  }

  async waitForEvent(type, opts) {
    return this._events.waitForEvent(type, opts);
  }

  async close() {
    if (this._browser) await this._browser.close();
  }
}
