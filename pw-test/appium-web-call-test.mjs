/**
 * Cross-platform тест: эмулятор (Android) ↔ веб (Flutter Web)
 *
 * Требования перед запуском:
 *   1. Appium сервер запущен: appium
 *   2. Эмулятор запущен и приложение открыто (или autoLaunch)
 *   3. Веб-сборка собрана: cd client && flutter build web
 *   4. Статический сервер запущен: cd pw-test && node serve-static-web.mjs
 *
 * Запуск: node appium-web-call-test.mjs
 */

import { remote } from "webdriverio";
import { chromium } from "playwright";
import { execSync } from "child_process";

const delay = (ms) => new Promise((r) => setTimeout(r, ms));
const BASE = process.env.STEALTH_WEB_URL || "http://127.0.0.1:58585";
const suffix = Date.now().toString(36);

const emulatorCaps = {
  platformName: "Android",
  "appium:deviceName": "emulator-5554",
  "appium:udid": "emulator-5554",
  "appium:automationName": "UiAutomator2",
  "appium:appPackage": "com.example.turbo",
  "appium:appActivity": ".MainActivity",
  "appium:noReset": true,
  "appium:fullReset": false,
  "appium:autoGrantPermissions": true,
};

const launchArgs = [
  "--use-fake-ui-for-media-stream",
  "--use-fake-device-for-media-stream",
];

const UUID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;

// ── Helpers ──────────────────────────────────────────────────────────────────

async function findElementByA11y(driver, id, timeout = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      const el = await driver.$(`~${id}`);
      if (await el.isDisplayed()) return el;
    } catch (_) {}
    await delay(500);
  }
  throw new Error(`Not found by a11y id: ${id}`);
}

async function clickByXPath(driver, xpath, timeout = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      const el = await driver.$(xpath);
      if (await el.isDisplayed()) {
        await el.click();
        return true;
      }
    } catch (_) {}
    await delay(500);
  }
  return false;
}

async function findTextInPageSource(driver) {
  const src = await driver.getPageSource();
  const m = src.match(UUID_RE);
  return m ? m[0] : null;
}

// ── Web (Playwright) ───────────────────────────────────────────────────────

async function enableFlutterA11y(page) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    const tb = await page.getByRole("textbox").count();
    const btn = await page.getByRole("button", { name: /GET STARTED/i }).count();
    if (tb > 0 || btn > 0) return true;
    await page.evaluate(() => {
      const b = document.querySelector('[aria-label="Enable accessibility"], flt-semantics-placeholder');
      if (b) b.click();
    });
    await delay(1000);
  }
  return false;
}

async function gotoApp(page) {
  const deadline = Date.now() + 120000;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      await page.goto(BASE, { waitUntil: "domcontentloaded", timeout: 15000 });
      for (let i = 0; i < 20 && Date.now() < deadline; i++) {
        const hasA11y = await page.evaluate(() =>
          !!document.querySelector('[aria-label="Enable accessibility"], flt-semantics-placeholder, input, textarea, [role="textbox"]')
        );
        if (hasA11y) return;
        await delay(1000);
      }
      await page.reload({ waitUntil: "domcontentloaded", timeout: 15000 });
    } catch (e) {
      lastErr = e;
      await delay(2000);
    }
  }
  throw new Error(`Cannot open ${BASE}: ${lastErr?.message}`);
}

async function registerWebUser(page, nickname) {
  await gotoApp(page);
  if (!(await enableFlutterA11y(page))) throw new Error("a11y failed");
  const field = page.getByRole("textbox").first();
  await field.waitFor({ state: "visible", timeout: 30000 });
  await field.click();
  await field.type(nickname);
  const btn = page.getByRole("button", { name: /GET STARTED/i });
  for (let i = 0; i < 20; i++) {
    if (await btn.isEnabled()) break;
    await delay(250);
  }
  await btn.click();
  await page.getByRole("button", { name: "Chats" }).waitFor({ state: "visible", timeout: 60000 });
}

async function readWebUserId(page) {
  // Стратегия 1: localStorage + stealthCrypto
  try {
    const id = await page.evaluate(async () => {
      for (let i = 0; i < 30; i++) {
        if (window.stealthCrypto) break;
        await new Promise((r) => setTimeout(r, 300));
      }
      if (!window.stealthCrypto) return null;
      const raw = localStorage.getItem("flutter.userId") || localStorage.getItem("userId");
      if (!raw) return null;
      let hex;
      try { hex = JSON.parse(raw); } catch (_) { hex = raw; }
      try { return await window.stealthCrypto.decrypt(hex); } catch (_) { return null; }
    });
    if (id && UUID_RE.test(id)) {
      console.log("  Web ID via localStorage:", id);
      return id;
    }
  } catch (_) {}

  // Стратегия 2: Profile UI
  console.log("  Fallback: reading Web ID from Profile UI...");
  await page.getByRole("button", { name: "Profile" }).click();
  await delay(4000);
  const id = await page.evaluate((pattern) => {
    const re = new RegExp(pattern, "i");
    for (const el of document.querySelectorAll("flt-semantics, [aria-label]")) {
      const m = (el.getAttribute("aria-label") || "").match(re) || (el.textContent || "").match(re);
      if (m) return m[0];
    }
    return null;
  }, "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
  if (id) {
    console.log("  Web ID via Profile UI:", id);
    return id;
  }
  throw new Error("Web UUID not found");
}

async function addContactWeb(page, targetId, targetNick) {
  console.log(`  Web: adding contact ${targetNick}...`);
  await page.getByRole("button", { name: "Contacts" }).click();
  await page.getByRole("button", { name: /Add contact/i }).click();

  // Вставляем UUID через clipboard + Paste ID
  await page.evaluate(async (id) => {
    try { await navigator.clipboard.writeText(id); } catch (_) {
      const ta = document.createElement("textarea");
      ta.value = id;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    }
  }, targetId);

  const searchField = page.locator('input[aria-label*="nickname" i], input[aria-label*="Search by" i]').first();
  await searchField.waitFor({ state: "visible", timeout: 15000 });
  await page.getByRole("button", { name: /Paste ID/i }).click();
  await delay(5000);

  // Ждем появления никнейма в результатах
  try {
    await page.getByText(targetNick, { exact: false }).first().waitFor({ state: "visible", timeout: 15000 });
  } catch (_) {
    console.log("  Warning: nickname not found in search results, continuing...");
  }

  await page.getByRole("button", { name: "Add", exact: true }).click();
  await delay(3000);
  console.log("  Web: contact added ✅");
}

// ── Emulator (Appium) ──────────────────────────────────────────────────────

async function readEmulatorUserId(driver) {
  console.log("  Emulator: opening Profile to read UUID...");
  await findElementByA11y(driver, "Profile", 15000).then((e) => e.click());
  await delay(4000);

  // Пробуем достать UUID из page source
  const fromSource = await findTextInPageSource(driver);
  if (fromSource) {
    console.log("  Emulator ID via page source:", fromSource);
    // Возвращаемся на Chats
    await findElementByA11y(driver, "Chats", 10000).then((e) => e.click());
    await delay(1000);
    return fromSource;
  }

  // Fallback: сохраняем скриншот для ручного чтения
  await driver.saveScreenshot("emulator-profile-uuid.png");
  console.log("  ⚠️  UUID not found in page source. Screenshot saved: emulator-profile-uuid.png");
  console.log("  Please read UUID manually and provide it.");

  // Возвращаемся
  await findElementByA11y(driver, "Chats", 10000).then((e) => e.click());
  await delay(1000);
  return null;
}

async function addContactEmulator(driver, targetId) {
  console.log("  Emulator: adding contact...");
  await findElementByA11y(driver, "Contacts", 15000).then((e) => e.click());
  await delay(2000);

  // XPath для Add contact
  const addClicked = await clickByXPath(
    driver,
    "//*[contains(@text, 'Add contact') or contains(@content-desc, 'Add contact') or contains(@resource-id, 'add')]",
    10000,
  );
  if (!addClicked) {
    console.log("  Warning: Add contact button not found, trying generic Add...");
    await clickByXPath(driver, "//android.widget.Button[contains(@text, 'Add')]", 5000);
  }
  await delay(2000);

  // Вводим UUID
  const searchField = await driver.$("//android.widget.EditText");
  if (await searchField.isDisplayed()) {
    await searchField.setValue(targetId);
    await delay(3000);
  }

  // Нажимаем Add в результатах
  await clickByXPath(driver, "//*[contains(@text, 'Add') or contains(@content-desc, 'Add')]", 5000);
  await delay(3000);
  await driver.saveScreenshot("emulator-contact-added.png");
  console.log("  Emulator: contact added ✅");
}

async function initiateCallFromEmulator(driver) {
  console.log("  Emulator: initiating call...");
  await findElementByA11y(driver, "Contacts", 15000).then((e) => e.click());
  await delay(2000);

  const callClicked = await clickByXPath(
    driver,
    "//*[contains(@content-desc, 'Start call') or contains(@text, 'Start call')]",
    10000,
  );
  if (callClicked) {
    console.log("  Emulator: call initiated ✅");
  } else {
    console.log("  ⚠️  Start call button not found. Screenshot saved for debug.");
    await driver.saveScreenshot("emulator-no-call-btn.png");
  }
}

// ── Main ───────────────────────────────────────────────────────────────────

async function main() {
  console.log("🚀 Cross-platform test: Emulator ↔ Web\n");

  // 1. Appium — эмулятор
  console.log("📱 Connecting to emulator via Appium...");
  const emulator = await remote({
    protocol: "http",
    hostname: "127.0.0.1",
    port: 4723,
    path: "/",
    capabilities: emulatorCaps,
  });
  console.log("✅ Emulator connected");

  // Даем приложению время загрузиться
  await delay(8000);

  // 2. Playwright — веб
  console.log("🌐 Launching browser...");
  const browser = await chromium.launch({
    headless: false,
    args: launchArgs,
  });
  const ctx = await browser.newContext({
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    viewport: { width: 900, height: 800 },
  });
  const web = await ctx.newPage();

  try {
    // ── Регистрация веб-пользователя ──
    const webNick = `Web_${suffix}`;
    console.log(`\n� Registering web user: ${webNick}`);
    await registerWebUser(web, webNick);
    const webId = await readWebUserId(web);
    console.log(`✅ Web user ID: ${webId}`);

    // ── Регистрация эмулятора и получение его ID ──
    console.log("\n📝 Reading emulator user ID...");
    const emulatorId = await readEmulatorUserId(emulator);
    if (!emulatorId) {
      throw new Error("Cannot read emulator UUID automatically. Pre-seed contacts or run manually.");
    }
    console.log(`✅ Emulator user ID: ${emulatorId}`);

    // ── Добавляем контакты друг к другу ──
    console.log("\n📋 Adding contacts cross-device...");
    await addContactWeb(web, emulatorId, `Emulator_${suffix}`);
    await addContactEmulator(emulator, webId);

    // ── Эмулятор инициирует звонок ──
    console.log("\n📞 Initiating call from emulator...");
    await initiateCallFromEmulator(emulator);
    await delay(3000);

    // ── Веб принимает входящий звонок ──
    console.log("\n🌐 Web: waiting for incoming call...");
    try {
      await web.getByText("Incoming call", { exact: false }).waitFor({ state: "visible", timeout: 30000 });
      console.log("✅ Incoming call detected on web");
      await web.getByRole("button", { name: /Answer/i }).click();
      console.log("✅ Call answered on web");
    } catch (e) {
      console.log("⚠️  No incoming call on web:", e.message);
      await web.screenshot({ path: "web-no-incoming.png" });
    }

    // ── Ждем установления соединения ──
    console.log("\n⏳ Waiting for connection (15s)...");
    await delay(15000);

    // ── Скриншоты ──
    await web.screenshot({ path: "web-call-screen.png" });
    await emulator.saveScreenshot("emulator-call-screen.png");
    console.log("\n📸 Screenshots saved: web-call-screen.png, emulator-call-screen.png");

    // ── WebRTC аудит на вебе ──
    console.log("\n🔍 WebRTC audio audit on web...");
    const webAudio = await web.evaluate(() => {
      const videos = document.querySelectorAll("video");
      const result = { videoElements: [], allStreams: [] };

      videos.forEach((v, idx) => {
        if (v.srcObject) {
          result.videoElements.push({
            index: idx,
            audioTracks: v.srcObject.getAudioTracks().map((t) => ({
              id: t.id,
              kind: t.kind,
              readyState: t.readyState,
              enabled: t.enabled,
              muted: t.muted,
              label: t.label,
            })),
            videoTracks: v.srcObject.getVideoTracks().map((t) => ({
              id: t.id,
              kind: t.kind,
              readyState: t.readyState,
              enabled: t.enabled,
              label: t.label,
            })),
          });
        }
      });

      // Ищем глобальные stream переменные
      for (const key of Object.keys(window)) {
        const val = window[key];
        if (val && val.getAudioTracks && typeof val.getAudioTracks === "function") {
          result.allStreams.push({
            source: key,
            audioTracks: val.getAudioTracks().map((t) => ({
              id: t.id,
              readyState: t.readyState,
              enabled: t.enabled,
              muted: t.muted,
              label: t.label,
            })),
          });
        }
      }

      // Проверяем audio элементы
      const audios = document.querySelectorAll("audio");
      result.audioElements = Array.from(audios).map((a) => ({
        paused: a.paused,
        muted: a.muted,
        volume: a.volume,
        srcObject: !!a.srcObject,
      }));

      return result;
    });
    console.log("WebRTC audit result:", JSON.stringify(webAudio, null, 2));

    // ── WebRTC аудит на эмуляторе (через logcat) ──
    console.log("\n🔍 Checking emulator logs...");
    try {
      const logs = execSync('adb -s emulator-5554 logcat -d -s flutter -b main | grep -E "stealth-call|rtc-stats|audio" | tail -20', {
        encoding: 'utf-8',
        timeout: 10000,
      });
      console.log("Emulator logcat (last 20 lines):\n", logs);
    } catch (e) {
      console.log("  Could not read emulator logs:", e.message);
    }

    console.log("\n✅ Test completed. Check screenshots and logs above.");

  } catch (err) {
    console.error("\n❌ Error:", err.message);
    try { await web?.screenshot({ path: "web-error.png" }); } catch (_) {}
    try { await emulator?.saveScreenshot("emulator-error.png"); } catch (_) {}
    throw err;
  } finally {
    await browser?.close();
    await emulator?.deleteSession();
  }
}

main().catch((err) => {
  console.error("\n❌ Fatal:", err?.message ?? err);
  process.exit(1);
});
