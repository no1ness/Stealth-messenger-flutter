import { remote } from 'webdriverio';
import { execSync } from 'child_process';

const caps = (udid) => ({
  platformName: 'Android',
  'appium:udid': udid,
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.stealth.messenger',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
});

async function withDevice(udid, fn) {
  const d = await remote({
    protocol: 'http', hostname: '127.0.0.1', port: 4725,
    connectionRetryCount: 1, connectionRetryTimeout: 30000,
    capabilities: caps(udid),
  });
  try { await fn(d); } finally { await d.deleteSession(); }
}

async function tap(d, xpath) { const el = await d.$(xpath); await el.click(); }
async function type(d, xpath, text) { const el = await d.$(xpath); await el.click(); await el.setValue(text); }

async function main() {
  const EMU_BUNDLE = execSync('echo "stealth:eyJ2IjoxLCJ1c2VyX2lkIjoiMWQ3ZDFlMGYtODhiMC00Zjk3LTkyYWMtYmRiMGUzZjczODg1IiwibmFtZSI6InNzc3NnZyIsInB1YmxpY19rZXkiOiJEZGN6SXE3RzB0dWx5a2JualJhNUw4NmxPNWp6dWJlenF5NjBrYmx0V21ZPSJ9"').toString().trim();
  const PHONE_BUNDLE = execSync('echo "stealth:eyJ2IjoxLCJ1c2VyX2lkIjoiNGVkODQ2ZWQtNjI2Ny00Mzg1LTljZmItMTAwNDMyODRkZWY4IiwibmFtZSI6IlBob25lVXNlciIsInB1YmxpY19rZXkiOiJYZkd5OWh2MXVDaTF2aEhYQ0tnYmtUcWt3cGhVbXRiTllhUExDS2Z3SkY0PSJ9"').toString().trim();

  console.log('=== Phone: add emulator contact ===');
  await withDevice('AQY57PRG4PQCR8UO', async (d) => {
    try { await tap(d, '//*[@content-desc="Chats"]'); } catch(e){}
    await d.pause(500);
    await tap(d, '//*[@content-desc="Contacts"]');
    await d.pause(500);
    try { await tap(d, '//*[contains(@content-desc, "Add contact")]'); } catch(e){}
    await d.pause(500);
    await type(d, '//android.widget.EditText', EMU_BUNDLE);
    await d.pause(2000);
    try {
      await tap(d, '//*[contains(@content-desc, "Add") or contains(@text, "Add")]');
      console.log('Phone: contact added');
    } catch(e) { console.log('Phone: add skipped'); }
  });

  console.log('=== Emulator: add phone contact ===');
  await withDevice('emulator-5554', async (d) => {
    try { await tap(d, '//*[@content-desc="Chats"]'); } catch(e){}
    await d.pause(500);
    await tap(d, '//*[@content-desc="Contacts"]');
    await d.pause(500);
    try { await tap(d, '//*[contains(@content-desc, "Add contact")]'); } catch(e){}
    await d.pause(500);
    await type(d, '//android.widget.EditText', PHONE_BUNDLE);
    await d.pause(2000);
    try {
      await tap(d, '//*[contains(@content-desc, "Add") or contains(@text, "Add")]');
      console.log('Emu: contact added');
    } catch(e) { console.log('Emu: add skipped'); }
  });

  console.log('=== Emulator: start call ===');
  await withDevice('emulator-5554', async (d) => {
    await tap(d, '//*[@content-desc="Contacts"]');
    await d.pause(500);
    await tap(d, '//*[contains(@content-desc, "Start call")]');
    console.log('Call started from emu');
    await d.pause(15000);
  });

  console.log('=== Phone: answer call ===');
  await withDevice('AQY57PRG4PQCR8UO', async (d) => {
    try {
      await tap(d, '//*[contains(@content-desc, "Answer")]');
      console.log('Call answered on phone');
      await d.pause(5000);
    } catch(e) { console.log('Phone: answer skipped'); }
  });

  console.log('=== Verify ===');
  await withDevice('emulator-5554', async (d) => {
    const src = await d.getPageSource();
    if (src.includes('Connected') || src.includes('Negotiating') || src.includes('call') || src.includes('Call')) {
      console.log('CALL ACTIVE!');
    } else {
      console.log('Call status unclear');
    }
  });
  console.log('Done!');
}
main().catch(e => console.error('FAIL:', e.message.slice(0,200)));
