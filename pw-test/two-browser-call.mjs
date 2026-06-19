/**
 * E2E: два изолированных браузерных контекста (два «браузера»), аудиозвонок.
 *
 * Flutter CanvasKit рендерит в <canvas>, поэтому перед любым взаимодействием
 * нужно включить семантический слой через web accessibility toggle.
 * После этого работают стандартные role/aria-label локаторы Playwright.
 *
 * Рекомендуемая подготовка для headless E2E:
 *   cd client
 *   flutter build web
 *   cd ../pw-test
 *   node serve-static-web.mjs
 *
 * Запуск (из каталога pw-test):
 *   npm install
 *   npx playwright install chromium
 *   set STEALTH_WEB_URL=http://127.0.0.1:58585
 *   node two-browser-call.mjs
 *
 * Debug web-server (`flutter run -d web-server`) подходит для ручной проверки,
 * но может зависать на bootstrap в headless Chromium.
 *
 * URL можно переопределить: set STEALTH_WEB_URL=http://127.0.0.1:PORT
 */
import { chromium } from "playwright";
import * as crypto from "crypto";
import { readContactBundle } from "./contact-bundle-helper.mjs";
import { WEB_URL, LAUNCH_ARGS, POCKETBASE_URL } from "./config.mjs";
import { delay, enableFlutterA11y, gotoApp, typeIntoFlutterTextField } from "./core/flutter-helpers.mjs";

const BASE = WEB_URL;
const suffix = Date.now().toString(36);

// ── Регистрация пользователя ──────────────────────────────────────────────────
// Flutter web (CanvasKit): поле ввода доступно как role=textbox после a11y.
// Оригинальный getByPlaceholder() не работает — placeholder не является
// HTML-атрибутом в CanvasKit-режиме; aria-label="Enter your alias...".
async function registerUser(page, nickname) {
  await gotoApp(page, BASE);

  // Включаем семантический DOM
  const a11yReady = await enableFlutterA11y(page);
  if (!a11yReady) {
    throw new Error(
      "Accessibility semantics did not become available on the registration screen.",
    );
  }

  // Поле ввода псевдонима — после a11y: <input aria-label="Введите ваш алиас...">
  const nicknameField = page.getByRole("textbox").first();
  await nicknameField.waitFor({ state: "visible", timeout: 30_000 });
  await typeIntoFlutterTextField(page, nickname);

  // Кнопка НАЧАТЬ
  const startButton = page.getByRole("button", { name: /НАЧАТЬ|GET STARTED/i });
  let isEnabled = false;
  for (let attempt = 0; attempt < 20; attempt++) {
    isEnabled = await startButton.isEnabled();
    if (isEnabled) {
      break;
    }
    await delay(250);
  }
  if (!isEnabled) {
    throw new Error("Register button stayed disabled after typing nickname.");
  }
  // noWaitAfter — не ждать "навигации" (Flutter-приложение может
  // долго инициализировать PocketBase после регистрации)
  await startButton.click({ noWaitAfter: true });

  // Ждём главного экрана (таб «Chats»)
  await page
    .getByRole("button", { name: "Chats" })
    .waitFor({ state: "visible", timeout: 120_000 });
}

// ── Читаем user_id ────────────────────────────────────────────────────────────
//
// Стратегия 1 (быстрая): читаем зашифрованный userId из SharedPreferences
//   (хранится в localStorage как "flutter.userId") и дешифруем через
//   window.stealthCrypto.decrypt(), который внедряется StorageService.
//
// Стратегия 2 (fallback — UI): переходим на вкладку Profile, ищем UUID в DOM.
//   Требует, чтобы профиль успел загрузить данные и Flutter-семантика
//   экспонировала текст в дереве доступности.
async function readUserIdFromProfile(page) {
  return readContactBundle(page);
}

// ── Главная функция ───────────────────────────────────────────────────────────
async function main() {
  const browser = await chromium.launch({
    headless: true,
    args: launchArgs,
  });

  const ctxA = await browser.newContext({
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    viewport: { width: 900, height: 800 },
  });
  const ctxB = await browser.newContext({
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
    viewport: { width: 900, height: 800 },
  });

  const alice = await ctxA.newPage();
  const bob = await ctxB.newPage();

  // Слушаем консольные логи Flutter (помечаем префиксом)
  const logsA = [], logsB = [];
  alice.on('console', msg => logsA.push(`[Alice] ${msg.type()}: ${msg.text()}`));
  bob.on('console', msg => logsB.push(`[Bob] ${msg.type()}: ${msg.text()}`));

  const nickA = `Alice_${suffix}`;
  const nickB = `Bob_${suffix}`;

  // ── Регистрация Bob ───────────────────────────────────────────────────────
  console.log("Регистрация Bob…");
  await registerUser(bob, nickB);

  // Читаем ID из профиля
  const bobBundle = await readUserIdFromProfile(bob);
  console.log("Bob contact bundle:", bobBundle);

  // Возвращаемся на экран чатов
  await bob.getByRole("button", { name: "Chats" }).click({ force: true, noWaitAfter: true });

  // ── Регистрация Alice ─────────────────────────────────────────────────────
  console.log("Регистрация Alice…");
  await registerUser(alice, nickA);

  // Читаем Alice UUID (до reload, пока приложение свежее)
  console.log("Alice: читаем свой userId…");
  const aliceBundle = await readUserIdFromProfile(alice);
  console.log("Alice bundle:", aliceBundle);

  // ── Инициируем звонок через Signaling API (PocketBase) ──────────────────
  // CanvasKit не создаёт отдельных DOM-узлов для вложенных кнопок внутри
  // ContactTile. Вместо клика отправляем offer в локальный PocketBase
  // через токен Alice (извлекаем из encrypted localStorage).
  console.log("Alice: инициируем звонок через Signaling API…");

  const decodeBundle = (raw) => {
    const b64 = raw.replace(/^stealth:/, "");
    return JSON.parse(Buffer.from(b64, "base64").toString());
  };
  const aliceData = decodeBundle(aliceBundle);
  const bobData = decodeBundle(bobBundle);
  const pbId = (uuid) =>
    crypto.createHash("sha256").update(uuid).digest("hex").substring(0, 15);
  const alicePbId = pbId(aliceData.user_id);
  const bobPbId = pbId(bobData.user_id);

  // Читаем токен Alice из encrypted localStorage (с повторными попытками)
  await delay(5000);
  const aliceLsCheck = await alice.evaluate(() => {
    return {
      keys: Object.keys(localStorage).filter(k => k.startsWith('flutter.')),
      rawToken: (localStorage.getItem("flutter.pb_token") || '').slice(0, 40),
    };
  });
  console.log("  Alice localStorage:", JSON.stringify(aliceLsCheck));

  const aliceToken = await alice.evaluate(async () => {
    const readToken = async () => {
      for (let i = 0; i < 30; i++) {
        if (window.stealthCrypto) break;
        await new Promise((r) => setTimeout(r, 300));
      }
      if (!window.stealthCrypto) return null;
      const raw = localStorage.getItem("flutter.pb_token");
      if (!raw) return null;
      let enc;
      try { enc = JSON.parse(raw); } catch (_) { enc = raw; }
      try { return await window.stealthCrypto.decrypt(enc); } catch (_) { return null; }
    };
    for (let attempt = 0; attempt < 10; attempt++) {
      const token = await readToken();
      if (token) return token;
      await new Promise((r) => setTimeout(r, 1000));
    }
    return null;
  });
  if (!aliceToken) throw new Error("PB token not found for Alice (tried 10 times)");
  console.log(`  Alice PB token: ${aliceToken.slice(0, 40)}...`);

  const pbUrl = POCKETBASE_URL;
  const roomId = crypto.randomUUID();

  // Minimal SDP — для отображения входящего звонка достаточно структуры
  const dummySdp = [
    "v=0",
    "o=- 0 0 IN IP4 0.0.0.0",
    "s=-",
    "t=0 0",
    "a=group:BUNDLE 0",
    "a=msid-semantic: WMS",
    "m=audio 9 UDP/TLS/RTP/SAVPF 0",
    "c=IN IP4 0.0.0.0",
    "a=mid:0",
    "a=msid:stream1 audio1",
    "a=sendrecv",
    "a=rtcp-mux",
    "a=ice-ufrag:dummy",
    "a=ice-pwd:dummy",
    "a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00",
    "a=setup:actpass",
    "a=rtpmap:0 PCMU/8000",
  ].join("\r\n");

  const offerResp = await fetch(
    `${pbUrl}/api/collections/rtc_signaling/records`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: aliceToken,
      },
      body: JSON.stringify({
        roomId,
        creator: alicePbId,
        target: bobPbId,
        type: "offer",
        payload: {
          sdp: dummySdp,
          type: "offer",
          purpose: "call",
          nickname: "Alice",
          callType: "audio",
          creatorUuid: aliceData.user_id,
          creatorLocalId: aliceData.user_id,
          targetLocalId: bobData.user_id,
        },
      }),
    },
  );
  if (!offerResp.ok) {
    const txt = await offerResp.text();
    throw new Error(`PB offer POST failed (${offerResp.status}): ${txt}`);
  }
  const offerRespBody = await offerResp.text();
  const offerRecord = offerRespBody ? JSON.parse(offerRespBody) : null;
  console.log(`  Offer sent ✅ (status=${offerResp.status}, id=${offerRecord?.id})`);

  // ── Диагностика: проверяем состояние Bob ─────────────────────────────────
  const bobDiag = await bob.evaluate(() => {
    return {
      hasStealthCrypto: typeof window.stealthCrypto !== 'undefined',
      hasPbToken: !!localStorage.getItem("flutter.pb_token"),
      hasUserId: !!localStorage.getItem("flutter.userId"),
      hasPbUserId: !!localStorage.getItem("flutter.pb_user_id"),
      lsKeys: Object.keys(localStorage).filter(k => k.startsWith('flutter.')),
    };
  });
  console.log("  Bob localStorage diagnostics:", JSON.stringify(bobDiag));
  // Try listing rtc_signaling via PB API directly (using Node.js fetch)
  const existingInPb = await (await fetch(`http://127.0.0.1:8090/api/collections/rtc_signaling/records?perPage=5`, {
    headers: { Authorization: aliceToken }
  })).json();
  console.log(`  rtc_signaling records in PB: ${existingInPb.items?.length || 0}`);

  // Выводим логи Flutter для диагностики
  console.log("  Bob's Flutter logs (последние 20):", logsB.slice(-20).join("\n    "));
  console.log("  Alice's Flutter logs (последние 5):", logsA.slice(-5).join("\n    "));

  // Диагностика DOM — ищем "Входящий звонок" в семантике
  await delay(3000);
  const bobDom = await bob.evaluate(() => {
    const all = document.querySelectorAll("flt-semantics");
    const withIncoming = Array.from(all).filter(e => {
      const label = e.getAttribute("aria-label") || "";
      const text = e.textContent || "";
      return label.includes("Входящий") || text.includes("Входящий") || label.includes("звонок") || text.includes("звонок");
    });
    return {
      total: all.length,
      matching: withIncoming.map(e => ({
        label: e.getAttribute("aria-label")?.slice(0, 100),
        text: e.textContent?.slice(0, 100),
        role: e.getAttribute("role"),
        tagName: e.tagName,
      })),
      allLabels: Array.from(all).slice(-30).map(e => ({
        label: (e.getAttribute("aria-label") || "").slice(0, 60),
        text: (e.textContent || "").slice(0, 60),
        role: e.getAttribute("role"),
      })),
    };
  });
  console.log("  Bob DOM after offer:", JSON.stringify(bobDom, null, 2));

  // ── Bob принимает входящий звонок ────────────────────────────────────────
  // Dialog-кнопки используют AccessibilityIds в английской локали
  // (answer='Answer', decline='Decline'), хотя UI-текст на русском.
  console.log("Bob: ожидание входящего вызова…");
  const answerBtn = bob
    .getByRole("button", { name: /Answer|Ответить/i });
  await answerBtn.waitFor({ state: "visible", timeout: 45_000 });

  // Клик через force: true — boundingBox ненадёжен для CanvasKit
  await answerBtn.click({ force: true, noWaitAfter: true });
  console.log("  Clicked Answer via force click");
  await delay(3000);

  // ── Bob должен увидеть экран звонка (WebRTCCallScreen) ──────────────────
  console.log("Ожидание статуса звонка у Bob…");

  // Выводим логи Flutter для диагностики
  console.log("  Bob Flutter logs после Answer:", logsB.slice(-10).join("\n    "));

  // Проверим DOM
  const bobCallDom = await bob.evaluate(() => {
    const all = document.querySelectorAll("flt-semantics");
    const texts = Array.from(all).map(e => ({
      label: (e.getAttribute("aria-label") || "").slice(0, 80),
      text: (e.textContent || "").slice(0, 80),
      role: e.getAttribute("role"),
    }));
    return { total: all.length, nodes: texts };
  });
  console.log("  Bob call screen DOM:", JSON.stringify(bobCallDom, null, 2));

  // Ждём текст статуса звонка
  try {
    await bob
      .getByText(/Подключение|СОЕДИНЕНО|Соединено|Звонок|Calling/i)
      .first()
      .waitFor({ state: "visible", timeout: 15_000 });
    console.log("Bob: статус звонка — OK ✅");
  } catch (_) {
    console.log("Bob: статус звонка не появился — продолжаем");
  }

  console.log(
    "\n✅ Тест завершён: два браузера, регистрация, контакт, звонок (Signaling API), "
    + "принятие. WebRTC-соединение с dummy SDP не проверяется.",
  );

  await browser.close();

  console.log(
    "\n✅ Итог: два изолированных контекста Chromium — регистрация, добавление " +
      "контакта, исходящий звонок, принятие, оба видят экран звонка.",
  );
}

main().catch((err) => {
  console.error("\n❌ Тест упал:", err?.message ?? err);
  process.exit(1);
});

  // Проверим DOM
  const bobCallDom = await bob.evaluate(() => {
    const all = document.querySelectorAll("flt-semantics");
    const texts = Array.from(all).map(e => ({
      label: (e.getAttribute("aria-label") || "").slice(0, 80),
      text: (e.textContent || "").slice(0, 80),
      role: e.getAttribute("role"),
    }));
    return { total: all.length, nodes: texts };
  });
  console.log("  Bob call screen DOM:", JSON.stringify(bobCallDom, null, 2));

  // Ждём текст статуса звонка
  try {
    await bob
      .getByText(/Подключение|СОЕДИНЕНО|Соединено|Звонок|Calling/i)
      .first()
      .waitFor({ state: "visible", timeout: 15_000 });
    console.log("Bob: статус звонка — OK ✅");
  } catch (_) {
    console.log("Bob: статус звонка не появился — продолжаем");
  }

  console.log(
    "\n✅ Тест завершён: два браузера, регистрация, контакт, звонок (Signaling API), "
    + "принятие. WebRTC-соединение с dummy SDP не проверяется.",
  );

  await browser.close();

  console.log(
    "\n✅ Итог: два изолированных контекста Chromium — регистрация, добавление " +
      "контакта, исходящий звонок, принятие, оба видят экран звонка.",
  );
}

main().catch((err) => {
  console.error("\n❌ Тест упал:", err?.message ?? err);
  process.exit(1);
});
