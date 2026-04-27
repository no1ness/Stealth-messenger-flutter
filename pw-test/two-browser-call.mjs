/**
 * E2E: два изолированных браузерных контекста (два «браузера»), аудиозвонок.
 *
 * Flutter CanvasKit рендерит в <canvas>, поэтому перед любым взаимодействием
 * нужно включить семантический слой через web accessibility toggle.
 * После этого работают стандартные role/aria-label локаторы Playwright.
 *
 * Подготовка:
 *   cd client
 *   flutter run -d web-server --web-hostname=127.0.0.1 --web-port=57575
 *
 * Запуск (из каталога pw-test):
 *   npm install
 *   npx playwright install chromium
 *   node two-browser-call.mjs
 *
 * URL можно переопределить: set STEALTH_WEB_URL=http://127.0.0.1:PORT
 */
import { chromium } from "playwright";

const BASE = process.env.STEALTH_WEB_URL || "http://127.0.0.1:57575";
const suffix = Date.now().toString(36);

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

const launchArgs = [
  "--use-fake-ui-for-media-stream",
  "--use-fake-device-for-media-stream",
];

async function getBootstrapState(page) {
  return page.evaluate(() => ({
    hasA11yToggle: !!document.querySelector(
      '[aria-label="Enable accessibility"], flt-semantics-placeholder',
    ),
    hasTextbox: !!document.querySelector('input, textarea, [role="textbox"]'),
    hasLoadingIndicator: !!document.querySelector("#loading_indicator"),
    bodyLength: document.body?.innerHTML?.length ?? 0,
  }));
}

// ── Flutter CanvasKit: включить семантический слой ────────────────────────────
// В новых Flutter web runtime триггер доступности доступен как off-screen
// элемент с aria-label="Enable accessibility". Обычный .click() падает из-за
// позиции вне viewport, поэтому включаем semantics через JS и ждём появления
// реальных доступных контролов.
async function enableFlutterA11y(page) {
  const deadline = Date.now() + 30_000;

  while (Date.now() < deadline) {
    const textboxCount = await page.getByRole("textbox").count();
    const startButtonCount = await page
      .getByRole("button", { name: /GET STARTED/i })
      .count();

    if (textboxCount > 0 || startButtonCount > 0) {
      return true;
    }

    const result = await page.evaluate(() => {
      const btn = document.querySelector(
        '[aria-label="Enable accessibility"], flt-semantics-placeholder',
      );
      if (!btn) return "NOT_FOUND";
      btn.click();
      return "CLICKED";
    });

    if (result === "CLICKED") {
      for (let attempt = 0; attempt < 10; attempt++) {
        await delay(1000);
        const textboxes = await page.getByRole("textbox").count();
        const startButtons = await page
          .getByRole("button", { name: /GET STARTED/i })
          .count();
        if (textboxes > 0 || startButtons > 0) {
          return true;
        }
      }
    } else {
      await delay(1000);
    }
  }

  return false;
}

// ── Открыть приложение (retry до 2 минут) ────────────────────────────────────
async function gotoApp(page) {
  const deadline = Date.now() + 120_000;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      await page.goto(BASE, { waitUntil: "domcontentloaded", timeout: 15_000 });
      for (let attempt = 0; attempt < 20 && Date.now() < deadline; attempt++) {
        const state = await getBootstrapState(page);
        if (state.hasA11yToggle || state.hasTextbox) {
          return;
        }
        await delay(1000);
      }

      await page.reload({ waitUntil: "domcontentloaded", timeout: 15_000 });
    } catch (e) {
      lastErr = e;
      await delay(2000);
    }
  }
  throw new Error(
    `Не удалось открыть ${BASE}. Запустите веб-сборку:\n` +
      `  cd client && flutter run -d web-server --web-hostname=127.0.0.1 --web-port=57575\n` +
      `Последняя ошибка: ${lastErr?.message || lastErr}`,
  );
}

// ── Регистрация пользователя ──────────────────────────────────────────────────
// Flutter web (CanvasKit): поле ввода доступно как role=textbox после a11y.
// Оригинальный getByPlaceholder() не работает — placeholder не является
// HTML-атрибутом в CanvasKit-режиме; aria-label="Enter your alias...".
async function registerUser(page, nickname) {
  await gotoApp(page);

  // Включаем семантический DOM
  const a11yReady = await enableFlutterA11y(page);
  if (!a11yReady) {
    throw new Error(
      "Accessibility semantics did not become available on the registration screen.",
    );
  }

  // Поле ввода псевдонима — после a11y: <input aria-label="Enter your alias...">
  const nicknameField = page.getByRole("textbox").first();
  await nicknameField.waitFor({ state: "visible", timeout: 30_000 });
  await nicknameField.click();
  await nicknameField.type(nickname);

  // Кнопка GET STARTED
  const startButton = page.getByRole("button", { name: /GET STARTED/i });
  let isEnabled = false;
  for (let attempt = 0; attempt < 20; attempt++) {
    isEnabled = await startButton.isEnabled();
    if (isEnabled) {
      break;
    }
    await delay(250);
  }
  if (!isEnabled) {
    throw new Error("GET STARTED button stayed disabled after typing nickname.");
  }
  await startButton.click();

  // Ждём главного экрана (таб «Chats»)
  await page
    .getByRole("button", { name: "Chats" })
    .waitFor({ state: "visible", timeout: 60_000 });
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
  const uuidRe =
    /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;

  // ── Стратегия 1: localStorage + stealthCrypto ────────────────────────────
  // Flutter SharedPreferences (web) хранит значения с префиксом "flutter.".
  // StorageService шифрует через Web Crypto API и инжектит window.stealthCrypto.
  try {
    const userId = await page.evaluate(async () => {
      // Ждём инициализации stealthCrypto (может не быть сразу после загрузки)
      for (let i = 0; i < 30; i++) {
        if (window.stealthCrypto) break;
        await new Promise((r) => setTimeout(r, 300));
      }
      if (!window.stealthCrypto) return null;

      // Flutter SharedPreferences (web) сохраняет значения как JSON-строки
      // (т.е. localStorage["flutter.userId"] = '"<hex>"').
      // Поэтому нужен JSON.parse() перед расшифровкой.
      const raw =
        localStorage.getItem("flutter.userId") ||
        localStorage.getItem("userId");
      if (!raw) return null;

      let encryptedHex;
      try {
        encryptedHex = JSON.parse(raw);
      } catch (_) {
        encryptedHex = raw;
      }

      try {
        return await window.stealthCrypto.decrypt(encryptedHex);
      } catch (_) {
        return null;
      }
    });

    if (userId && uuidRe.test(userId)) {
      console.log("  userId via localStorage decrypt:", userId);
      return userId;
    }
  } catch (e) {
    console.warn("  localStorage strategy failed:", e.message?.slice(0, 80));
  }

  // ── Стратегия 2: UI — экран профиля ─────────────────────────────────────
  console.log("  Fallback: читаем UUID из Profile screen…");
  await page.getByRole("button", { name: "Profile" }).click();

  // Ждём пока профиль загрузит данные и они появятся в DOM / семантике
  await delay(4000);

  // Ищем UUID в тексте всех flt-semantics узлов и aria-label
  const userId = await page.evaluate((pattern) => {
    const re = new RegExp(pattern, "i");
    for (const el of document.querySelectorAll("flt-semantics, [aria-label]")) {
      const label = el.getAttribute("aria-label") || "";
      const text = el.textContent || "";
      const m = label.match(re) || text.match(re);
      if (m) return m[0];
    }
    return null;
  }, "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");

  if (userId) {
    console.log("  userId via Profile DOM:", userId);
    return userId;
  }

  // Playwright getByText как последний вариант
  try {
    const loc = page.getByText(uuidRe);
    await loc.first().waitFor({ state: "visible", timeout: 15_000 });
    const text = await loc.first().innerText();
    const m = text.match(uuidRe);
    if (m) return m[0];
  } catch (_) {
    /* ignore */
  }

  throw new Error(
    "UUID не найден ни через localStorage, ни через Profile UI. " +
      "Проверьте что профиль загружается без ошибок.",
  );
}

// ── Локатор поля поиска контактов ────────────────────────────────────────────
// В CanvasKit: <input aria-label="Search by nickname or full user ID">
// getByPlaceholder() не работает (нет HTML placeholder атрибута).
function getContactSearchInput(page) {
  return page
    .locator(
      'input[aria-label*="nickname" i], input[aria-label*="Search by" i]',
    )
    .first();
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

  const nickA = `Alice_${suffix}`;
  const nickB = `Bob_${suffix}`;

  // ── Регистрация Bob ───────────────────────────────────────────────────────
  console.log("Регистрация Bob…");
  await registerUser(bob, nickB);

  // Читаем ID из профиля
  const bobId = await readUserIdFromProfile(bob);
  console.log("Bob user_id:", bobId);

  // Возвращаемся на экран чатов
  await bob.getByRole("button", { name: "Chats" }).click();

  // ── Регистрация Alice ─────────────────────────────────────────────────────
  console.log("Регистрация Alice…");
  await registerUser(alice, nickA);

  // ── Alice добавляет Bob в контакты ───────────────────────────────────────
  console.log("Alice: открываем Contacts…");
  await alice.getByRole("button", { name: "Contacts" }).click();

  console.log("Alice: нажимаем Add contact…");
  await alice.getByRole("button", { name: /Add contact/i }).click();

  // Вставляем Bob UUID через буфер обмена → кнопка "Paste ID" → одиночный search()
  // Это надёжнее чем keyboard.type(), который вызывает onChanged на КАЖДЫЙ символ
  // и создаёт 36 параллельных Supabase-запросов с race condition.
  console.log("Alice: копируем UUID Bob в буфер и нажимаем Paste ID…");
  await alice.evaluate(async (id) => {
    // Запись в clipboard
    try {
      await navigator.clipboard.writeText(id);
    } catch (_) {
      // Fallback: используем document.execCommand (deprecated но работает headless)
      const ta = document.createElement("textarea");
      ta.value = id;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    }
  }, bobId);

  // Ждём открытия модала (поле поиска должно быть видимым)
  const searchField = getContactSearchInput(alice);
  await searchField.waitFor({ state: "visible", timeout: 15_000 });

  // Нажимаем «Paste ID» — Flutter читает clipboard и вызывает search() один раз
  await alice.getByRole("button", { name: /Paste ID/i }).click();

  // Ждём завершения Supabase-запроса (один запрос вместо 36)
  console.log("Alice: ждём результаты поиска (единственный Supabase-запрос)…");
  await delay(5_000);

  // Ждём появления никнейма Bob в результатах модала
  try {
    await alice
      .getByText(nickB, { exact: false })
      .first()
      .waitFor({ state: "visible", timeout: 15_000 });
    console.log("Alice: нашли Bob в результатах поиска ✅");
  } catch (_) {
    console.log("Alice: nickname Bob не виден в результатах, продолжаем…");
  }

  console.log("Alice: подтверждаем добавление…");
  await alice.getByRole("button", { name: "Add", exact: true }).click();

  // Ждём закрытия модала и обновления списка контактов
  await delay(3_000);

  // Проверяем что Bob появился в списке контактов.
  // Flutter CanvasKit: текст карточек может быть в flt-semantics или aria-label.
  console.log("Alice: ждём карточку контакта Bob в списке…");
  let bobCardFound = false;

  // Попытка 1: Playwright getByText (работает если текст в семантическом дереве)
  try {
    await alice
      .getByText(nickB, { exact: false })
      .first()
      .waitFor({ state: "visible", timeout: 15_000 });
    bobCardFound = true;
    console.log("Alice: карточка Bob видна (getByText) ✅");
  } catch (_) {
    console.log("Alice: getByText не нашёл карточку Bob, пробуем aria…");
  }

  // Попытка 2: aria-label содержит nickB
  if (!bobCardFound) {
    try {
      await alice
        .locator(`[aria-label*="${nickB}"]`)
        .first()
        .waitFor({ state: "visible", timeout: 10_000 });
      bobCardFound = true;
      console.log("Alice: карточка Bob видна (aria-label) ✅");
    } catch (_) {
      console.warn("Alice: aria-label не нашёл карточку Bob.");
    }
  }

  // Попытка 3: снимок экрана для диагностики
  if (!bobCardFound) {
    await alice.screenshot({ path: "dbg-contacts-after-add.png" });
    console.warn(
      "Alice: карточка Bob не найдена в DOM. Скриншот → dbg-contacts-after-add.png.",
    );
  }

  // ── Alice инициирует звонок ───────────────────────────────────────────────
  // Контактная карточка отображает кнопки прямо на карточке:
  // [чат] [📞 Start call] [📹 Start video call] [⋯ More options]
  // Кнопка «Start call» получила tooltip в contacts_screen.dart, поэтому
  // доступна через getByRole("button", { name: "Start call" }).
  console.log("Alice: нажимаем кнопку Start call на карточке контакта…");
  await alice
    .getByRole("button", { name: "Start call" })
    .first()
    .waitFor({ state: "visible", timeout: 15_000 });
  await alice.getByRole("button", { name: "Start call" }).first().click();

  // ── Bob принимает входящий звонок ────────────────────────────────────────
  console.log("Bob: ожидание входящего вызова…");
  await bob
    .getByText("Incoming call", { exact: false })
    .waitFor({ state: "visible", timeout: 45_000 });

  await bob.getByRole("button", { name: /Answer/i }).click();

  // ── Оба должны увидеть статус звонка ─────────────────────────────────────
  console.log("Ожидание статуса Connected / Negotiating у Alice…");
  await alice
    .getByText(/Connected|Negotiating/i)
    .first()
    .waitFor({ state: "visible", timeout: 90_000 });
  console.log("Alice: статус звонка — OK ✅");

  console.log("Ожидание статуса Connected / Negotiating у Bob…");
  await bob
    .getByText(/Connected|Negotiating/i)
    .first()
    .waitFor({ state: "visible", timeout: 90_000 });
  console.log("Bob: статус звонка — OK ✅");

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
