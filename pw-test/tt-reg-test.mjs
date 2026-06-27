import { chromium } from 'playwright';

const baseURL = 'http://127.0.0.1:58587';

const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });

// ===== Telegram-TT: register Bob =====
const ttCtx = await browser.newContext({ viewport: { width: 900, height: 800 } });
const ttPage = await ttCtx.newPage();
const ttLogs = [];
ttPage.on('console', msg => ttLogs.push(`[TT ${msg.type()}] ${msg.text()}`));
ttPage.on('pageerror', err => ttLogs.push('[TT ERROR] ' + err.message));

await ttPage.goto(baseURL, { waitUntil: 'commit', timeout: 30000 });
console.log('Waiting for TT to load...');

// Wait for textbox (phone input)
const textbox = ttPage.getByRole('textbox').first();
await textbox.waitFor({ state: 'visible', timeout: 60000 });
console.log('TT phone input visible');

// Type nickname
const bobSuffix = Date.now().toString(36);
await textbox.click();
await textbox.fill(`TTBob_${bobSuffix}`);
console.log(`TT typed nickname: TTBob_${bobSuffix}`);

// Find and click Next button - try multiple selectors
const nextBtn = ttPage.locator('button[title="Next"], button:has(svg), .btn-primary, [data-testid="next"]').first();
const anyBtn = ttPage.getByRole('button').first();
console.log('First button text:', await anyBtn.textContent().catch(() => 'N/A'));

// Try clicking the login/next button
const loginBtn = ttPage.locator('.login-btn, .btn-primary, button:has(.icon-next), .after-button');
if (await loginBtn.count() > 0) {
  await loginBtn.first().click();
} else {
  // Press Enter
  await ttPage.keyboard.press('Enter');
}

await new Promise(r => setTimeout(r), 5000);

// Check current state
const chatBtn = ttPage.getByRole('button', { name: /Chats|Чаты/i });
const visible = await chatBtn.isVisible().catch(() => false);
console.log('Chats button visible:', visible);
console.log('Current URL:', ttPage.url());

// Screenshot
await ttPage.screenshot({ path: '/tmp/tt-after-reg.png', type: 'png' });

// Show last few console logs
console.log('\n=== TT console logs (last 20) ===');
for (const log of ttLogs.slice(-20)) console.log(log);

await browser.close();
