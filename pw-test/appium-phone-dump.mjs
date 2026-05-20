/**
 * Только дамп page source телефона
 */
import { remote } from 'webdriverio';
import { writeFileSync } from 'fs';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

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
  console.log('📱 Подключение к телефону...');
  const driver = await remote({
    protocol: 'http', hostname: '127.0.0.1', port: 4723, path: '/',
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
