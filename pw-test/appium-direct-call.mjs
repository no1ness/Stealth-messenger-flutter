/**
 * Прямой тест звонка - без получения User ID
 * Просто находим первый контакт и звоним
 */

import { remote } from 'webdriverio';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

const emulatorCaps = {
  platformName: 'Android',
  'appium:deviceName': 'emulator-5554',
  'appium:udid': 'emulator-5554',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.stealth.messenger',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
};

const phoneCaps = {
  platformName: 'Android',
  'appium:deviceName': '2412DPC0AG',
  'appium:udid': 'AQY57PRG4PQCR8UO',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.stealth.messenger',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
};

async function main() {
  console.log('🚀 Прямой тест звонка\n');

  console.log('📱 Подключение к телефону...');
  const phone = await remote({
    protocol: 'http',
    hostname: '127.0.0.1',
    port: 4723,
    path: '/',
    capabilities: phoneCaps,
  });

  try {
    console.log('⏳ Ожидание 5 секунд...');
    await delay(5000);

    // Сохраняем скриншот
    await phone.saveScreenshot('direct-phone-start.png');
    console.log('📸 Скриншот: direct-phone-start.png');

    // Переходим на Contacts
    console.log('\n📱 Переходим на Contacts...');
    const contactsTab = await phone.$('~Contacts');
    await contactsTab.click();
    await delay(2000);

    await phone.saveScreenshot('direct-phone-contacts.png');
    console.log('📸 Скриншот: direct-phone-contacts.png');

    // Ищем кнопку "Start call"
    console.log('\n📱 Ищем кнопку "Start call"...');
    const callButton = await phone.$('~Start call');

    if (await callButton.isDisplayed()) {
      console.log('✅ Кнопка найдена! Нажимаем...');
      await callButton.click();
      await delay(3000);

      await phone.saveScreenshot('direct-phone-calling.png');
      console.log('📸 Скриншот: direct-phone-calling.png');

      console.log('\n✅ Звонок инициирован с телефона!');
      console.log('⏳ Держим звонок активным 10 секунд...');
      await delay(10000);

      await phone.saveScreenshot('direct-phone-call-active.png');
      console.log('📸 Скриншот: direct-phone-call-active.png');
    } else {
      console.log('❌ Кнопка "Start call" не найдена');
      console.log('ℹ️  Возможно нет контактов');
    }

  } catch (error) {
    console.error('\n❌ ОШИБКА:', error.message);
    await phone.saveScreenshot('direct-phone-error.png');
    console.log('📸 Скриншот ошибки: direct-phone-error.png');
    throw error;
  } finally {
    console.log('\n🔌 Закрываем сессию...');
    await phone.deleteSession();
  }
}

main().catch((err) => {
  console.error('\n❌ Тест упал:', err?.message ?? err);
  process.exit(1);
});
