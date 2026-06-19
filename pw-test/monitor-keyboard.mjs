import { chromium } from 'playwright';

const b = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
const p = await b.newPage();
await p.goto("about:blank");

// Set up event monitoring
await p.evaluate(() => {
  window.addEventListener('keydown', e => console.log('EVT keydown', { key: e.key, code: e.code, trusted: e.isTrusted }));
  window.addEventListener('keyup', e => console.log('EVT keyup', { key: e.key, code: e.code, trusted: e.isTrusted }));
  window.addEventListener('beforeinput', e => console.log('EVT beforeinput', { inputType: e.inputType, data: e.data, trusted: e.isTrusted, target: e.target.tagName }));
  window.addEventListener('input', e => console.log('EVT input', { inputType: e.inputType, data: e.data, trusted: e.isTrusted, target: e.target.tagName }));
});

// Create an input and focus it
await p.evaluate(() => {
  document.body.innerHTML = '<input id="test" placeholder="test">';
  document.getElementById('test').focus();
});

await new Promise(r => setTimeout(r, 500));

// Type using Playwright
console.log('--- Playwright keyboard.type ---');
await p.keyboard.type("ab", { delay: 200 });

await new Promise(r => setTimeout(r, 1000));

// Now type using evaluate
console.log('--- Evaluate InputEvent ---');
await p.evaluate(() => {
  const inp = document.getElementById('test');
  inp.value = inp.value + 'cd';
  inp.dispatchEvent(new InputEvent('beforeinput', {
    inputType: 'insertText', data: 'cd', bubbles: true,
  }));
  inp.dispatchEvent(new InputEvent('input', {
    inputType: 'insertText', data: 'cd', bubbles: true,
  }));
});

await new Promise(r => setTimeout(r, 500));

console.log('--- Final value ---');
const val = await p.evaluate(() => document.getElementById('test').value);
console.log('Input value:', JSON.stringify(val));

await b.close();
