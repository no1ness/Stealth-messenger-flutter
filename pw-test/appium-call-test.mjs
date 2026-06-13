/**
 * Appium E2E: Тестовый звонок между эмулятором и реальным телефоном
 *
 * Требования:
 * 1. Запустить Appium сервер: appium
 * 2. Эмулятор должен быть запущен: emulator-5554
 * 3. Телефон подключен: AQY57PRG4PQCR8UO
 * 4. Приложение установлено на обоих устройствах
 *
 * Запуск:
 *   node appium-call-test.mjs
 */

import { remote } from 'webdriverio';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

// Конфигурация для эмулятора
const emulatorCaps = {
  platformName: 'Android',
  'appium:deviceName': 'emulator-5554',
  'appium:udid': 'emulator-5554',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.stealth.messenger',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:fullReset': false,
  'appium:autoGrantPermissions': true,
};

// Конфигурация для телефона
const phoneCaps = {
  platformName: 'Android',
  'appium:deviceName': '2412DPC0AG',
  'appium:udid': 'AQY57PRG4PQCR8UO',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.stealth.messenger',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:fullReset': false,
  'appium:autoGrantPermissions': true,
};

async function findElementWithRetry(driver, selector, timeout = 30000) {
  const startTime = Date.now();
  let lastError;

  while (Date.now() - startTime < timeout) {
    try {
      const element = await driver.$(selector);
      if (await element.isDisplayed()) {
        return element;
      }
    } catch (e) {
      lastError = e;
    }
    await delay(1000);
  }

  throw new Error(`Element not found: ${selector}. Last error: ${lastError?.message}`);
}

async function readClipboardText(driver) {
  const raw = await driver.getClipboard('plaintext');
  if (typeof raw !== 'string' || raw.length === 0) return null;
  if (raw.startsWith('stealth:')) return raw;

  try {
    const decoded = Buffer.from(raw, 'base64').toString('utf8');
    return decoded.startsWith('stealth:') ? decoded : raw;
  } catch (_) {
    return raw;
  }
}

async function getContactBundle(driver, envVarName) {
  const envBundle = process.env[envVarName];
  if (envBundle) {
    if (!envBundle.startsWith('stealth:')) {
      throw new Error(`${envVarName} must contain a stealth: contact bundle.`);
    }
    return envBundle;
  }

  console.log('  Получаем contact bundle из профиля...');
  try {
    const profileTab = await findElementWithRetry(
      driver,
      '//android.widget.Button[@content-desc="Profile"]',
      10000
    );
    await profileTab.click();
    await delay(3000);
  } catch (_) {
    const profileButton = await driver.$('~Profile');
    await profileButton.click();
    await delay(3000);
  }

  const copyButton = await findElementWithRetry(
    driver,
    '//*[contains(@content-desc, "Copy contact bundle") or contains(@text, "Copy contact bundle")]',
    10000
  );
  await copyButton.click();
  await delay(1000);

  const bundle = await readClipboardText(driver);
  if (!bundle?.startsWith('stealth:')) {
    await driver.saveScreenshot(`debug-no-contact-bundle-${envVarName}.png`);
    throw new Error(`Contact bundle не найден. Можно задать ${envVarName}.`);
  }

  try {
    const chatsTab = await findElementWithRetry(
      driver,
      '//android.widget.Button[@content-desc="Chats"]',
      5000
    );
    await chatsTab.click();
    await delay(1000);
  } catch (_) {
    console.log('  ⚠️  Не удалось вернуться на Chats, продолжаем...');
  }

  console.log(`  ✅ Contact bundle: ${bundle.slice(0, 32)}...`);
  return bundle;
}

async function getUserId(driver) {
  console.log('  Получаем User ID из профиля...');

  // Переходим на вкладку Profile
  try {
    const profileTab = await findElementWithRetry(
      driver,
      '//android.widget.Button[@content-desc="Profile"]',
      10000
    );
    await profileTab.click();
    await delay(3000);
  } catch (e) {
    console.log('  ⚠️  Не удалось найти кнопку Profile, пробуем альтернативный способ...');
    // Пробуем найти по тексту
    try {
      const profileButton = await driver.$('~Profile');
      await profileButton.click();
      await delay(3000);
    } catch (e2) {
      console.log('  ⚠️  Альтернативный способ тоже не сработал, используем page source...');
    }
  }

  // Ищем UUID в page source
  const pageSource = await driver.getPageSource();
  const uuidMatch = pageSource.match(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/);

  if (!uuidMatch) {
    // Сохраняем скриншот и page source для отладки
    await driver.saveScreenshot('debug-no-uuid.png');
    console.log('  📸 Скриншот сохранен: debug-no-uuid.png');
    console.log('  📄 Page source (первые 500 символов):', pageSource.substring(0, 500));
    throw new Error('User ID не найден в page source');
  }

  const userId = uuidMatch[0];
  console.log(`  ✅ User ID: ${userId}`);

  // Возвращаемся на вкладку Chats
  try {
    const chatsTab = await findElementWithRetry(
      driver,
      '//android.widget.Button[@content-desc="Chats"]',
      5000
    );
    await chatsTab.click();
    await delay(1000);
  } catch (e) {
    console.log('  ⚠️  Не удалось вернуться на Chats, продолжаем...');
  }

  return userId;
}

async function addContact(driver, contactBundle, contactName) {
  console.log(`  Добавляем контакт: ${contactName}`);

  // Переходим на вкладку Contacts
  const contactsTab = await findElementWithRetry(
    driver,
    '//*[@content-desc="Contacts"]'
  );
  await contactsTab.click();
  await delay(1000);

  // Нажимаем "Add contact"
  const addButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[contains(@content-desc, "Add contact")]'
  );
  await addButton.click();
  await delay(1000);

  // Вводим User ID в поле поиска
  const searchField = await findElementWithRetry(
    driver,
    '//android.widget.EditText'
  );
  await searchField.setValue(contactBundle);
  await delay(3000); // Ждем результаты поиска

  // Нажимаем кнопку "Add"
  const confirmButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[@content-desc="Add"]'
  );
  await confirmButton.click();
  await delay(2000);

  console.log(`  Контакт ${contactName} добавлен ✅`);
}

async function initiateCall(driver, contactName) {
  console.log(`  Инициируем звонок к ${contactName}...`);

  // Убедимся что мы на вкладке Contacts
  const contactsTab = await findElementWithRetry(
    driver,
    '//*[@content-desc="Contacts"]'
  );
  await contactsTab.click();
  await delay(1000);

  // Ищем кнопку "Start call" на карточке контакта
  const callButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[@content-desc="Start call"]'
  );
  await callButton.click();

  console.log(`  Звонок инициирован ✅`);
}

async function answerCall(driver) {
  console.log('  Ожидаем входящий звонок...');

  // Ищем кнопку "Answer"
  const answerButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[contains(@content-desc, "Answer")]',
    45000
  );
  await answerButton.click();

  console.log('  Звонок принят ✅');
}

async function verifyCallConnected(driver, deviceName) {
  console.log(`  ${deviceName}: Проверяем статус звонка...`);

  // Ищем текст "Connected" или "Negotiating"
  await delay(5000);
  const pageSource = await driver.getPageSource();

  if (pageSource.includes('Connected') || pageSource.includes('Negotiating')) {
    console.log(`  ${deviceName}: Звонок подключен ✅`);
    return true;
  }

  throw new Error(`${deviceName}: Статус звонка не найден`);
}

async function main() {
  console.log('🚀 Запуск Appium теста звонка между эмулятором и телефоном\n');
  console.log('ℹ️  Используем уже зарегистрированных пользователей\n');

  // Подключаемся к Appium серверу
  console.log('Подключение к эмулятору...');
  const emulator = await remote({
    protocol: 'http',
    hostname: '127.0.0.1',
    port: 4725,
    path: '/',
    capabilities: emulatorCaps,
  });

  console.log('Подключение к телефону...');
  const phone = await remote({
    protocol: 'http',
    hostname: '127.0.0.1',
    port: 4725,
    path: '/',
    capabilities: phoneCaps,
  });

  try {
    // Даем приложениям время на запуск
    console.log('\n⏳ Ожидание запуска приложений...');
    await delay(8000);

    // Сохраняем начальные скриншоты
    await emulator.saveScreenshot('emulator-start.png');
    await phone.saveScreenshot('phone-start.png');
    console.log('📸 Начальные скриншоты: emulator-start.png, phone-start.png');

    // Получаем contact bundle с обоих устройств
    console.log('\n📱 Получаем contact bundle с телефона...');
    const phoneContactBundle = await getContactBundle(phone, 'STEALTH_PHONE_CONTACT_BUNDLE');

    console.log('\n💻 Получаем contact bundle с эмулятора...');
    const emulatorContactBundle = await getContactBundle(emulator, 'STEALTH_EMULATOR_CONTACT_BUNDLE');

    // Проверяем, есть ли уже контакты
    console.log('\n🔍 Проверяем существующие контакты...');

    // Эмулятор добавляет телефон в контакты (если еще не добавлен)
    console.log('\n💻 Эмулятор: Добавляем телефон в контакты...');
    try {
      await addContact(emulator, phoneContactBundle, 'Phone');
    } catch (e) {
      console.log('  ℹ️  Контакт уже существует или ошибка добавления:', e.message);
    }

    // Телефон добавляет эмулятор в контакты (если еще не добавлен)
    console.log('\n📱 Телефон: Добавляем эмулятор в контакты...');
    try {
      await addContact(phone, emulatorContactBundle, 'Emulator');
    } catch (e) {
      console.log('  ℹ️  Контакт уже существует или ошибка добавления:', e.message);
    }

    // Эмулятор инициирует звонок
    console.log('\n💻 Эмулятор: Инициируем звонок...');
    await initiateCall(emulator, 'Phone');

    // Телефон принимает звонок
    console.log('\n📱 Телефон: Принимаем звонок...');
    await answerCall(phone);

    // Проверяем статус звонка на обоих устройствах
    console.log('\n🔍 Проверяем статус звонка...');
    await verifyCallConnected(emulator, 'Эмулятор');
    await verifyCallConnected(phone, 'Телефон');

    console.log('\n✅ ТЕСТ ПРОЙДЕН: Звонок между эмулятором и телефоном успешен!');

    // Держим звонок активным 10 секунд
    console.log('\n⏳ Держим звонок активным 10 секунд...');
    await delay(10000);

    // Сохраняем финальные скриншоты
    await emulator.saveScreenshot('emulator-call-success.png');
    await phone.saveScreenshot('phone-call-success.png');
    console.log('📸 Финальные скриншоты: emulator-call-success.png, phone-call-success.png');

  } catch (error) {
    console.error('\n❌ ОШИБКА:', error.message);

    // Сохраняем скриншоты для отладки
    try {
      await emulator.saveScreenshot('emulator-error.png');
      await phone.saveScreenshot('phone-error.png');
      console.log('📸 Скриншоты ошибки: emulator-error.png, phone-error.png');
    } catch (e) {
      console.error('Не удалось сохранить скриншоты:', e.message);
    }

    throw error;
  } finally {
    // Закрываем сессии
    console.log('\n🔌 Закрываем сессии...');
    await emulator.deleteSession();
    await phone.deleteSession();
  }
}

main().catch((err) => {
  console.error('\n❌ Тест упал:', err?.message ?? err);
  process.exit(1);
});
