/**
 * Тест звонка с детальными логами
 * Запускает приложение на обоих устройствах и собирает логи
 */

import { spawn } from 'child_process';
import { writeFileSync } from 'fs';
import { EMULATOR_UDID, PHONE_UDID } from './config.mjs';

const delay = (ms) => new Promise(r => setTimeout(r, ms));

// Логи для каждого устройства
const phoneLogs = [];
const emulatorLogs = [];

const phoneUdid = PHONE_UDID || process.env.STEALTH_PHONE_UDID;
const emulatorUdid = EMULATOR_UDID;

if (!phoneUdid) {
  console.error('ERROR: STEALTH_PHONE_UDID not set');
  process.exit(1);
}

// Запускаем сбор логов с телефона
const phoneLogcat = spawn('adb', ['-s', phoneUdid, 'logcat', '-v', 'time', 'flutter:V', 'stealth:V', '*:S']);
phoneLogcat.stdout.on('data', (data) => {
  const line = data.toString();
  phoneLogs.push(line);
  if (line.includes('[stealth-call]') || line.includes('[rtc-stats]')) {
    console.log(`📱 PHONE: ${line.trim()}`);
  }
});

// Запускаем сбор логов с эмулятора
const emulatorLogcat = spawn('adb', ['-s', emulatorUdid, 'logcat', '-v', 'time', 'flutter:V', 'stealth:V', '*:S']);
emulatorLogcat.stdout.on('data', (data) => {
  const line = data.toString();
  emulatorLogs.push(line);
  if (line.includes('[stealth-call]') || line.includes('[rtc-stats]')) {
    console.log(`💻 EMULATOR: ${line.trim()}`);
  }
});

console.log('🎙️  Сбор логов запущен...');
console.log('📝 Теперь совершите звонок вручную между устройствами');
console.log('⏱️  Логи будут собираться 60 секунд...\n');

// Собираем логи 60 секунд
await delay(60000);

// Останавливаем сбор логов
phoneLogcat.kill();
emulatorLogcat.kill();

// Сохраняем логи в файлы
writeFileSync('phone-call-logs.txt', phoneLogs.join(''));
writeFileSync('emulator-call-logs.txt', emulatorLogs.join(''));

console.log('\n✅ Логи сохранены:');
console.log('   - phone-call-logs.txt');
console.log('   - emulator-call-logs.txt');
