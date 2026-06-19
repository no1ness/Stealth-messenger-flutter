/**
 * Appium helper functions for Android E2E tests
 * 
 * Provides common utilities for:
 * - Element finding with retry
 * - Clipboard operations
 * - Contact bundle operations
 * - Common UI interactions
 */

export const delay = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Find element with retry logic
 */
export async function findElementWithRetry(driver, selector, timeout = 30000) {
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

/**
 * Read clipboard text with base64 decoding fallback
 */
export async function readClipboardText(driver) {
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

/**
 * Get contact bundle from environment variable or profile screen
 */
export async function getContactBundle(driver, envVarName) {
  const envBundle = process.env[envVarName];
  if (envBundle) {
    if (!envBundle.startsWith('stealth:')) {
      throw new Error(`${envVarName} must contain a stealth: contact bundle.`);
    }
    return envBundle;
  }

  console.log(`  Getting contact bundle from profile...`);
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
    throw new Error(`Contact bundle not found. Set ${envVarName}.`);
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
    console.log('  ⚠️  Could not return to Chats, continuing...');
  }

  console.log(`  ✅ Contact bundle: ${bundle.slice(0, 32)}...`);
  return bundle;
}

/**
 * Get user ID from profile screen
 */
export async function getUserId(driver) {
  console.log('  Getting User ID from profile...');

  try {
    const profileTab = await findElementWithRetry(
      driver,
      '//android.widget.Button[@content-desc="Profile"]',
      10000
    );
    await profileTab.click();
    await delay(3000);
  } catch (e) {
    console.log('  ⚠️  Profile button not found, trying alternative...');
    try {
      const profileButton = await driver.$('~Profile');
      await profileButton.click();
      await delay(3000);
    } catch (e2) {
      console.log('  ⚠️  Alternative also failed, using page source...');
    }
  }

  const pageSource = await driver.getPageSource();
  const uuidMatch = pageSource.match(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/);

  if (!uuidMatch) {
    await driver.saveScreenshot('debug-no-uuid.png');
    console.log('  📸 Screenshot saved: debug-no-uuid.png');
    console.log('  📄 Page source (first 500 chars):', pageSource.substring(0, 500));
    throw new Error('User ID not found in page source');
  }

  const userId = uuidMatch[0];
  console.log(`  ✅ User ID: ${userId}`);

  try {
    const chatsTab = await findElementWithRetry(
      driver,
      '//android.widget.Button[@content-desc="Chats"]',
      5000
    );
    await chatsTab.click();
    await delay(1000);
  } catch (e) {
    console.log('  ⚠️  Could not return to Chats, continuing...');
  }

  return userId;
}

/**
 * Add contact via UI
 */
export async function addContact(driver, contactBundle, contactName) {
  console.log(`  Adding contact: ${contactName}`);

  const contactsTab = await findElementWithRetry(
    driver,
    '//*[@content-desc="Contacts"]'
  );
  await contactsTab.click();
  await delay(1000);

  const addButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[contains(@content-desc, "Add contact")]'
  );
  await addButton.click();
  await delay(1000);

  const searchField = await findElementWithRetry(
    driver,
    '//android.widget.EditText'
  );
  await searchField.setValue(contactBundle);
  await delay(3000);

  const confirmButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[@content-desc="Add"]'
  );
  await confirmButton.click();
  await delay(2000);

  console.log(`  Contact ${contactName} added ✅`);
}

/**
 * Initiate call via UI
 */
export async function initiateCall(driver, contactName) {
  console.log(`  Initiating call to ${contactName}...`);

  const contactsTab = await findElementWithRetry(
    driver,
    '//*[@content-desc="Contacts"]'
  );
  await contactsTab.click();
  await delay(1000);

  const callButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[@content-desc="Start call"]'
  );
  await callButton.click();

  console.log(`  Call initiated ✅`);
}

/**
 * Answer incoming call via UI
 */
export async function answerCall(driver) {
  console.log('  Waiting for incoming call...');

  const answerButton = await findElementWithRetry(
    driver,
    '//android.widget.Button[contains(@content-desc, "Answer")]',
    45000
  );
  await answerButton.click();

  console.log('  Call answered ✅');
}

/**
 * Verify call connected status
 */
export async function verifyCallConnected(driver, deviceName) {
  console.log(`  ${deviceName}: Checking call status...`);

  await delay(5000);
  const pageSource = await driver.getPageSource();

  if (pageSource.includes('Connected') || pageSource.includes('Negotiating')) {
    console.log(`  ${deviceName}: Call connected ✅`);
    return true;
  }

  throw new Error(`${deviceName}: Call status not found`);
}
