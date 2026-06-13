import { remote } from 'webdriverio';

const caps = (udid) => ({
  platformName: 'Android',
  'appium:udid': udid,
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.stealth.messenger',
  'appium:noReset': true,
  'appium:autoGrantPermissions': true,
});

const EMU_BUNDLE = 'stealth:eyJ2IjoxLCJ1c2VyX2lkIjoiMWQ3ZDFlMGYtODhiMC00Zjk3LTkyYWMtYmRiMGUzZjczODg1IiwibmFtZSI6InNzc3NnZyIsInB1YmxpY19rZXkiOiJEZGN6SXE3RzB0dWx5a2JualJhNUw4NmxPNWp6dWJlenF5NjBrYmx0V21ZPSJ9';
const PHONE_BUNDLE = 'stealth:eyJ2IjoxLCJ1c2VyX2lkIjoiNGVkODQ2ZWQtNjI2Ny00Mzg1LTljZmItMTAwNDMyODRkZWY4IiwibmFtZSI6IlBob25lVXNlciIsInB1YmxpY19rZXkiOiJYZkd5OWh2MXVDaTF2aEhYQ0tnYmtUcWt3cGhVbXRiTllhUExDS2Z3SkY0PSJ9';

async function connectDevice(udid) {
  const d = await remote({
    protocol: 'http', hostname: '127.0.0.1', port: 4725,
    connectionRetryCount: 1, connectionRetryTimeout: 30000,
    capabilities: caps(udid),
  });
  return d;
}

async function tap(d, xpath) {
  const el = await d.$(xpath);
  await el.click();
}

async function type(d, xpath, text) {
  const el = await d.$(xpath);
  await el.click();
  await el.setValue(text);
}

async function addContact(d, bundle) {
  try { await tap(d, '//*[@content-desc="Chats"]'); } catch(e) {}
  await d.pause(500);
  await tap(d, '//*[@content-desc="Contacts"]');
  await d.pause(500);
  try { await tap(d, '//*[contains(@content-desc, "Add contact")]'); } catch(e) {}
  await d.pause(500);
  await type(d, '//android.widget.EditText', bundle);
  await d.pause(2000);
  try {
    await tap(d, '//*[contains(@content-desc, "Add") or contains(@text, "Add")]');
    console.log('  Contact added');
  } catch(e) {
    console.log('  Add btn not found, contact may already exist');
  }
}

async function startCall(d) {
  await tap(d, '//*[@content-desc="Contacts"]');
  await d.pause(500);
  const btn = await d.$('//*[contains(@content-desc, "Start call")]');
  await btn.click();
  console.log('  Call initiated');
}

async function answerCall(d) {
  const btn = await d.$('//*[contains(@content-desc, "Answer")]');
  await btn.click();
  console.log('  Call answered');
}

async function main() {
  console.log('Connecting...');
  const phone = await connectDevice('AQY57PRG4PQCR8UO');
  console.log('Phone OK');
  const emu = await connectDevice('emulator-5554');
  console.log('Emu OK');

  console.log('Phone: add emulator contact');
  try { await addContact(phone, EMU_BUNDLE); } catch(e) { console.log('  skip:', e.message.slice(0,60)); }

  console.log('Emu: add phone contact');
  try { await addContact(emu, PHONE_BUNDLE); } catch(e) { console.log('  skip:', e.message.slice(0,60)); }

  console.log('Call from emulator...');
  try { await startCall(emu); } catch(e) { console.log('  skip:', e.message.slice(0,60)); }

  console.log('Phone answer...');
  try { await answerCall(phone); } catch(e) { console.log('  skip:', e.message.slice(0,60)); }

  await d.pause(5000);
  console.log('Checking call status...');
  const src = await emu.getPageSource();
  if (src.includes('Connected') || src.includes('Negotiating')) {
    console.log('CALL CONNECTED!');
  } else {
    console.log('Call status unknown');
  }

  await phone.deleteSession();
  await emu.deleteSession();
  console.log('Done');
}
main().catch(e => console.error('FAIL:', e.message.slice(0,200)));
