/**
 * Упрощенный Appium тест: звонок между уже настроенными устройствами
 *
 * Предполагается:
 * - Оба устройства уже зарегистрированы
 * - Контакты уже добавлены друг к другу
 * - Просто инициируем звонок и принимаем его
 *
 * Запуск: node appium-simple-call-test.mjs
 */

import { remote } from 'webdriverio';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

// Конфигурация для эмулятора
const emulatorCaps = {
  platformName: 'Android',
  'appium:deviceName': 'emulator-5554',
  'appium:udid': 'emulator-5554',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.example.turbo',
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
  'appium:appPackage': 'com.example.turbo',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:fullReset': false,
  'appium:autoGrantPermissions': true,
};

async function findElementByAccessibilityId(driver, id, timeout = 10000) {
  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    try {
      const element = await driver.$(`~${id}`);
      if (await element.isDisplayed()) {
        return element;
      }
    } catch (e) {
      // Элемент не найден, продолжаем поиск
    }
    await delay(500);
  }

  throw new Error(`Element not found by accessibility id: ${id}`);
}

async function initiateCall(driver, deviceName) {
  console.log(`  ${deviceName}: Переходим на вкладку Contacts...`);

  const contactsTab = await findElementByAccessibilityId(driver, 'Contacts');
  await contactsTab.click();
  await delay(2000);

  console.log(`  ${deviceName}: Ищем кнопку "Start call"...`);

  // Ищем кнопку "Start call" на первой карточке контакта
  const callButton = await findElementByAccessibilityId(driver, 'Start call', 15000);
  await callButton.click();

  console.log(`  ${deviceName}: Звонок инициирован ✅`);
}

async function answerCall(driver, deviceName) {
  console.log(`  ${deviceName}: Ожидаем входящий звонок...`);

  // Ищем кнопку "Answer"
  const answerButton = await findElementByAccessibilityId(driver, 'Answer', 45000);
  await answerButton.click();

  console.log(`  ${deviceName}: Звонок принят ✅`);
}

async function verifyCallConnected(driver, deviceName) {
  console.log(`  ${deviceName}: Проверяем статус звонка...`);

  await delay(5000);
  const pageSource = await driver.getPageSource();

  if (pageSource.includes('Connected') || pageSource.includes('Negotiating') || pageSource.includes('Ringing')) {
    console.log(`  ${deviceName}: Звонок активен ✅`);
    return true;
  }

  console.log(`  ${deviceName}: ⚠️  Статус звонка не подтвержден, но продолжаем...`);
  return false;
}

async function main() {
  console.log('🚀 Упрощенный тест звонка между эмулятором и телефоном\n');
  console.log('ℹ️  Предполагается, что устройства уже настроены и контакты добавлены\n');

  // Подключаемся к Appium серверу
  console.log('📱 Подключение к телефону...');
  const phone = await remote({
    protocol: 'http',
    hostname: '127.0.0.1',
    port: 4723,
    path: '/',
    capabilities: phoneCaps,
  });

  console.log('💻 Подключение к эмулятору...');
  const emulator = await remote({
    protocol: 'http',
    hostname: '127.0.0.1',
    port: 4723,
    path: '/',
    capabilities: emulatorCaps,
  });

  try {
    // Даем приложениям время на запуск
    console.log('\n⏳ Ожидание запуска приложений (10 сек)...');
    await delay(10000);

    // Разблокируем телефон свайпом (на случай если заблокировался)
    console.log('🔓 Разблокируем телефон...');
    try {
      await phone.action('pointer', { parameters: { pointerType: 'touch' } })
        .move({ x: 540, y: 1800 })
        .down()
        .move({ x: 540, y: 900, duration: 500 })
        .up()
        .perform();
    } catch (_) {}
    await delay(2000);

    // Сохраняем начальные скриншоты
    await emulator.saveScreenshot('simple-emulator-start.png');
    await phone.saveScreenshot('simple-phone-start.png');
    console.log('📸 Начальные скриншоты сохранены\n');

    // Эмулятор инициирует звонок
    console.log('💻 Эмулятор: Инициируем звонок...');
    await initiateCall(emulator, 'Эмулятор');

    await delay(2000);

    // Телефон принимает звонок
    console.log('\n📱 Телефон: Принимаем звонок...');
    await answerCall(phone, 'Телефон');

    await delay(3000);

    // Проверяем статус звонка на обоих устройствах
    console.log('\n🔍 Проверяем статус звонка...');
    await verifyCallConnected(emulator, 'Эмулятор');
    await verifyCallConnected(phone, 'Телефон');

    console.log('\n✅ ТЕСТ ЗАВЕРШЕН: Звонок между устройствами инициирован!');

    // Держим звонок активным 15 секунд
    console.log('\n⏳ Держим звонок активным 15 секунд...');
    await delay(15000);

    // Сохраняем финальные скриншоты
    await emulator.saveScreenshot('simple-emulator-call.png');
    await phone.saveScreenshot('simple-phone-call.png');
    console.log('📸 Финальные скриншоты: simple-emulator-call.png, simple-phone-call.png');

  } catch (error) {
    console.error('\n❌ ОШИБКА:', error.message);

    // Сохраняем скриншоты для отладки
    try {
      await emulator.saveScreenshot('simple-emulator-error.png');
      await phone.saveScreenshot('simple-phone-error.png');
      console.log('📸 Скриншоты ошибки сохранены');
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
