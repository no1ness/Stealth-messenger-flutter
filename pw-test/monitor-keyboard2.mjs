import { chromium } from 'playwright';

const b = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
const p = await b.newPage();
p.on('console', msg => {
  if (msg.text().startsWith('EVT ')) console.log(msg.text());
});
await p.goto("about:blank");

// Set up event monitoring
await p.evaluate(() => {
  window.addEventListener('keydown', e => console.log('EVT keydown', JSON.stringify({ key: e.key, code: e.code, trusted: e.isTrusted })));
  window.addEventListener('beforeinput', e => console.log('EVT beforeinput', JSON.stringify({ inputType: e.inputType, data: e.data, trusted: e.isTrusted, targetTag: e.target.tagName, targetId: e.target.id })));
  window.addEventListener('input', e => console.log('EVT input', JSON.stringify({ inputType: e.inputType, data: e.data, trusted: e.isTrusted, targetTag: e.target.tagName, targetId: e.target.id })));
});

// Create an input and focus it
await p.evaluate(() => {
  document.body.innerHTML = '<input id="test" placeholder="test">';
  document.getElementById('test').focus();
});

await new Promise(r => setTimeout(r, 500));

// Type using Playwright
console.log('--- Playwright keyboard.type ---');
await p.keyboard.type("x", { delay: 200 });

await new Promise(r => setTimeout(r, 500));

const val = await p.evaluate(() => document.getElementById('test').value);
console.log('--- Final value:', JSON.stringify(val), '---');

await b.close();
