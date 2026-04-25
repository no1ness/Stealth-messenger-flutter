/**
 * E2E: два изолированных браузерных контекста (два «браузера»), аудиозвонок.
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
import { chromium } from 'playwright';

const BASE = process.env.STEALTH_WEB_URL || 'http://127.0.0.1:57575';
const suffix = Date.now().toString(36);

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

const launchArgs = [
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
];

async function gotoApp(page) {
  const deadline = Date.now() + 120_000;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 15_000 });
      return;
    } catch (e) {
      lastErr = e;
      await delay(2000);
    }
  }
  throw new Error(
    `Не удалось открыть ${BASE}. Запустите веб-сборку: ` +
      `cd client && flutter run -d web-server --web-hostname=127.0.0.1 --web-port=57575\n` +
      `Последняя ошибка: ${lastErr?.message || lastErr}`,
  );
}

async function registerUser(page, nickname) {
  await gotoApp(page);
  await page.getByPlaceholder(/Enter your alias/i).fill(nickname);
  await page.getByRole('button', { name: /GET STARTED/i }).click();
  await page.getByRole('button', { name: 'Chats' }).waitFor({ state: 'visible', timeout: 60_000 });
}

/** UUID v4 в DOM (профиль). */
async function readUserIdFromProfile(page) {
  await page.getByRole('button', { name: 'Profile' }).click();
  const uuidRe = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;
  const loc = page.getByText(uuidRe);
  await loc.first().waitFor({ state: 'visible', timeout: 30_000 });
  const text = await loc.first().innerText();
  const m = text.match(uuidRe);
  if (!m) {
    throw new Error(`UUID не найден в профиле, текст: ${text.slice(0, 200)}`);
  }
  return m[0];
}

async function longPressCenter(page, locator) {
  const box = await locator.first().boundingBox();
  if (!box) {
    throw new Error('longPress: элемент без bounding box');
  }
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await delay(650);
  await page.mouse.up();
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    args: launchArgs,
  });

  const ctxA = await browser.newContext({
    permissions: ['microphone', 'camera'],
    viewport: { width: 900, height: 800 },
  });
  const ctxB = await browser.newContext({
    permissions: ['microphone', 'camera'],
    viewport: { width: 900, height: 800 },
  });

  const alice = await ctxA.newPage();
  const bob = await ctxB.newPage();

  const nickA = `Alice_${suffix}`;
  const nickB = `Bob_${suffix}`;

  console.log('Регистрация Bob…');
  await registerUser(bob, nickB);
  const bobId = await readUserIdFromProfile(bob);
  console.log('Bob user_id:', bobId);

  await bob.getByRole('button', { name: 'Chats' }).click();

  console.log('Регистрация Alice…');
  await registerUser(alice, nickA);

  console.log('Alice: добавить контакт Bob…');
  await alice.getByRole('button', { name: 'Contacts' }).click();
  await alice.getByRole('button', { name: /Add contact/i }).click();
  const search = alice.getByPlaceholder(/Search by nickname or full user ID/i);
  await search.fill(bobId);
  await delay(800);
  await alice.getByRole('button', { name: 'Add', exact: true }).click();
  await alice.getByText(nickB, { exact: false }).first().waitFor({ state: 'visible', timeout: 30_000 });

  console.log('Alice: долгое нажатие по карточке контакта → Start call…');
  await longPressCenter(alice, alice.getByText(nickB, { exact: false }).first());
  await alice.getByText('Start call', { exact: true }).click();

  console.log('Bob: ожидание входящего…');
  await bob.getByText('Incoming call', { exact: false }).waitFor({ state: 'visible', timeout: 45_000 });
  await bob.getByRole('button', { name: /Answer/i }).click();

  console.log('Ожидание состояния звонка (Connected или Negotiating)…');
  const callUi = alice.getByText(/Connected|Negotiating/i).first();
  await callUi.waitFor({ state: 'visible', timeout: 90_000 });
  console.log('Alice: вижу статус звонка — OK');

  await bob.getByText(/Connected|Negotiating/i).first().waitFor({ state: 'visible', timeout: 90_000 });
  console.log('Bob: вижу статус звонка — OK');

  await browser.close();
  console.log(
    '\nИтог: два изолированных контекста Chromium — входящий звонок, Answer, оба видят экран звонка (статус).',
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
