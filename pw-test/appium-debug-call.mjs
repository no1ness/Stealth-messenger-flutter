/**
 * Отладочный тест: инициируем звонок с эмулятора и дампим page source телефона
 */

import { remote } from 'webdriverio';
import { writeFileSync } from 'fs';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

const emulatorCaps = {
  platformName: 'Android',
  'appium:deviceName': 'emulator-5554',
  'appium:udid': 'emulator-5554',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.example.turbo',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
};

const phoneCaps = {
  platformName: 'Android',
  'appium:deviceName': '2412DPC0AG',
  'appium:udid': 'AQY57PRG4PQCR8UO',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.example.turbo',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
  'appium:unlockType': 'pin',
  'appium:skipUnlock': true,
};

async function findEl(driver, id, timeout = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      const el = await driver.$(`~${id}`);
      if (await el.isDisplayed()) return el;
    } catch (_) {}
    await delay(500);
  }
  throw new Error(`Not found: ${id}`);
}

async function main() {
  console.log('🔍 Отладочный тест звонка\n');

  console.log('📱 Подключение к телефону...');
  const phone = await remote({
    protocol: 'http', hostname: '127.0.0.1', port: 4723, path: '/',
    capabilities: phoneCaps,
  });

  console.log('💻 Подключение к эмулятору...');
  const emulator = await remote({
    protocol: 'http', hostname: '127.0.0.1', port: 4723, path: '/',
    capabilities: emulatorCaps,
  });

  try {
    console.log('\n⏳ Ждём 8 сек...');
    await delay(8000);

    // Скриншоты начального состояния
    await phone.saveScreenshot('debug-phone-initial.png');
    await emulator.saveScreenshot('debug-emulator-initial.png');
    console.log('📸 Начальные скриншоты сохранены');

    // Дамп page source эмулятора — проверяем контакты
    const emulatorSource = await emulator.getPageSource();
    writeFileSync('debug-emulator-source.xml', emulatorSource);
    const emulatorContentDescs = emulatorSource.match(/content-desc="[^"]+"/g) || [];
    console.log('\n💻 Эмулятор content-desc:');
    emulatorContentDescs.forEach(d => console.log('  ' + d));

    // Переходим на Contacts на эмуляторе
    console.log('\n💻 Эмулятор: переходим на Contacts...');
    const contactsTab = await findEl(emulator, 'Contacts');
    await contactsTab.click();
    await delay(2000);

    await emulator.saveScreenshot('debug-emulator-contacts.png');
    const contactsSource = await emulator.getPageSource();
    writeFileSync('debug-emulator-contacts.xml', contactsSource);
    const contactsDescs = contactsSource.match(/content-desc="[^"]+"/g) || [];
    console.log('\n💻 Эмулятор Contacts content-desc:');
    contactsDescs.forEach(d => console.log('  ' + d));

    // Проверяем есть ли Start call
    const hasStartCall = contactsDescs.some(d => d.includes('Start call'));
    console.log(`\n${hasStartCall ? '✅' : '❌'} "Start call" ${hasStartCall ? 'найден' : 'НЕ найден'}`);

    if (hasStartCall) {
      // Нажимаем Start call
      console.log('\n💻 Эмулятор: нажимаем Start call...');
      const callBtn = await findEl(emulator, 'Start call');
      await callBtn.click();
      console.log('✅ Нажато!');

      // Ждём 5 сек и дампим телефон
      console.log('\n⏳ Ждём 5 сек пока звонок дойдёт до телефона...');
      await delay(5000);

      await phone.saveScreenshot('debug-phone-incoming.png');
      const phoneSource = await phone.getPageSource();
      writeFileSync('debug-phone-source.xml', phoneSource);
      const phoneDescs = phoneSource.match(/content-desc="[^"]+"/g) || [];
      console.log('\n📱 Телефон content-desc после звонка:');
      phoneDescs.forEach(d => console.log('  ' + d));

      const hasAnswer = phoneDescs.some(d => d.includes('Answer'));
      console.log(`\n${hasAnswer ? '✅' : '❌'} "Answer" ${hasAnswer ? 'найден на телефоне!' : 'НЕ найден на телефоне'}`);

      if (hasAnswer) {
        console.log('\n📱 Телефон: нажимаем Answer...');
        const answerBtn = await findEl(phone, 'Answer');
        await answerBtn.click();
        console.log('✅ Звонок принят!');

        await delay(5000);
        await phone.saveScreenshot('debug-phone-call-active.png');
        await emulator.saveScreenshot('debug-emulator-call-active.png');

        const phoneCallSource = await phone.getPageSource();
        const phoneCallDescs = phoneCallSource.match(/content-desc="[^"]+"/g) || [];
        console.log('\n📱 Телефон во время звонка:');
        phoneCallDescs.forEach(d => console.log('  ' + d));

        console.log('\n✅ ТЕСТ УСПЕШЕН!');
      }
    }

  } finally {
    await phone.deleteSession();
    await emulator.deleteSession();
  }
}

main().catch(err => {
  console.error('❌ Ошибка:', err?.message ?? err);
  process.exit(1);
});
