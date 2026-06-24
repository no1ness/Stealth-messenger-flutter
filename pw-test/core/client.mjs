import { chromium } from "playwright";
import { WEB_URL, LAUNCH_ARGS, VIEWPORT, CONTEXT_PERMISSIONS, HEADLESS } from "../config.mjs";
import { EventBus } from "./events.mjs";
import { attachBridge } from "./bridge.mjs";
import { enableFlutterA11y, gotoApp } from "./flutter-helpers.mjs";
import { registerUser } from "./scenario-helpers.mjs";

export class Client {
  constructor(name, existingBrowser = null) {
    this.name = name;
    this._browser = existingBrowser;
    this._ownBrowser = existingBrowser === null;
    this._ctx = null;
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
    if (this._ownBrowser) {
      this._browser = await chromium.launch({ args: LAUNCH_ARGS, headless: HEADLESS });
    }
    this._ctx = await this._browser.newContext({
      viewport: VIEWPORT,
      permissions: CONTEXT_PERMISSIONS,
      locale: "en-US",
    });
    this._page = await this._ctx.newPage();
    await attachBridge(this._page, this._events);
    await this._page.goto(WEB_URL, { waitUntil: "commit", timeout: 30000 });
  }

  async register(nickname) {
    await registerUser(this, nickname);
  }

  async screenshot(path) {
    if (this._page) {
      await this._page.screenshot({ path });
    }
  }

  async resetToMain() {
    await gotoApp(this._page, WEB_URL);
    await enableFlutterA11y(this._page);
    await this._page
      .getByRole("button", { name: /Chats|Чаты/i })
      .waitFor({ state: "visible", timeout: 30000 });
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
    if (this._ctx) await this._ctx.close();
    if (this._ownBrowser && this._browser) await this._browser.close();
  }
}
