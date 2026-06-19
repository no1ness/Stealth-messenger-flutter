/**
 * Только дамп page source телефона
 */
import { remote } from 'webdriverio';
import { writeFileSync } from 'fs';
import { APPIUM_HOST, APPIUM_PORT, PHONE_UDID } from './config.mjs';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

const phoneCaps = {
  platformName: 'Android',
  'appium:deviceName': PHONE_UDID || process.env.STEALTH_PHONE_UDID || 'PHONE',
  'appium:udid': PHONE_UDID || process.env.STEALTH_PHONE_UDID,
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.stealth.messenger',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
};

async function main() {
  console.log('📱 Подключение к телефону...');
  const driver = await remote({
    protocol: 'http', hostname: APPIUM_HOST, port: APPIUM_PORT, path: '/',
    capabilities: phoneCaps,
  });

  try {
    console.log('⏳ Ждём 5 сек...');
    await delay(5000);

    await driver.saveScreenshot('phone-dump-screen.png');
    console.log('📸 Скриншот: phone-dump-screen.png');

    const source = await driver.getPageSource();
    writeFileSync('phone-dump-source.xml', source);
    console.log(`💾 Сохранено: phone-dump-source.xml (${source.length} символов)`);

    const descs = source.match(/content-desc="[^"]+"/g) || [];
    console.log(`\n🏷️  content-desc (${descs.length}):`);
    descs.forEach(d => console.log('  ' + d));

    // Проверяем текущий пакет
    const currentApp = await driver.getCurrentPackage();
    console.log(`\n📦 Текущий пакет: ${currentApp}`);

    const currentActivity = await driver.getCurrentActivity();
    console.log(`🎯 Текущая активность: ${currentActivity}`);

  } finally {
    await driver.deleteSession();
  }
}

main().catch(err => {
  console.error('❌ Ошибка:', err?.message ?? err);
  process.exit(1);
});
