/**
 * Диагностика: дампим page source и ищем content-desc атрибуты
 */

import { remote } from 'webdriverio';
import { writeFileSync } from 'fs';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

const phoneCaps = {
  platformName: 'Android',
  'appium:deviceName': '2412DPC0AG',
  'appium:udid': 'AQY57PRG4PQCR8UO',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.example.turbo',
  'appium:appActivity': '.MainActivity',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
};

async function main() {
  console.log('🔍 Диагностика Appium page source\n');

  const driver = await remote({
    protocol: 'http',
    hostname: '127.0.0.1',
    port: 4723,
    path: '/',
    capabilities: phoneCaps,
  });

  try {
    console.log('⏳ Ждём 8 секунд...');
    await delay(8000);

    await driver.saveScreenshot('dump-screen.png');
    console.log('📸 Скриншот: dump-screen.png');

    // Получаем page source
    console.log('\n📄 Получаем page source...');
    const source = await driver.getPageSource();

    // Сохраняем полный source
    writeFileSync('dump-page-source.xml', source);
    console.log('💾 Сохранено: dump-page-source.xml');
    console.log(`📏 Размер: ${source.length} символов`);

    // Ищем content-desc атрибуты
    const contentDescMatches = source.match(/content-desc="[^"]+"/g) || [];
    console.log(`\n🏷️  Найдено content-desc атрибутов: ${contentDescMatches.length}`);
    if (contentDescMatches.length > 0) {
      console.log('Список:');
      contentDescMatches.forEach(m => console.log('  ' + m));
    } else {
      console.log('❌ content-desc атрибуты НЕ найдены!');
    }

    // Ищем Flutter-специфичные элементы
    const flutterElements = source.match(/class="[^"]*Flutter[^"]*"/g) || [];
    console.log(`\n🐦 Flutter элементы: ${flutterElements.length}`);
    flutterElements.slice(0, 5).forEach(m => console.log('  ' + m));

    // Показываем первые 2000 символов source
    console.log('\n📋 Первые 1500 символов page source:');
    console.log(source.substring(0, 1500));

  } finally {
    await driver.deleteSession();
  }
}

main().catch(err => {
  console.error('❌ Ошибка:', err?.message ?? err);
  process.exit(1);
});
