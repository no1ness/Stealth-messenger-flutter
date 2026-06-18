import { chromium } from "playwright";
import { WEB_URL, LAUNCH_ARGS } from "../config.mjs";
import { EventBus } from "./events.mjs";

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
    const ctx = await this._browser.newContext();
    this._page = await ctx.newPage();
    await this._page.goto(WEB_URL, { waitUntil: "domcontentloaded" });
    await this._ensureA11y();
  }

  async _ensureA11y() {
    const hasToggle = await this._page.evaluate(() =>
      !!document.querySelector(
        '[aria-label="Enable accessibility"], flt-semantics-placeholder',
      ),
    );
    if (hasToggle) {
      const toggle = await this._page.$('[aria-label="Enable accessibility"]');
      if (toggle) await toggle.click();
      await this._page.waitForTimeout(500);
    }
  }

  async waitForSelector(selector, { timeout = 15000 } = {}) {
    await this._page.waitForSelector(selector, { timeout });
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
