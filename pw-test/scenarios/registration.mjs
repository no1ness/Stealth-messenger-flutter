export default async function registration({ alice, bob }) {
  const nicknameA = "Alice_" + Date.now().toString(36);
  const nicknameB = "Bob_" + Date.now().toString(36);

  await alice.waitForSelector('[role="button"]', { timeout: 30000 });
  await alice.page.evaluate((nick) => {
    const inputs = document.querySelectorAll('flt-semantics [role="text"]');
    const input = inputs[inputs.length - 1];
    if (input) input.focus();
  }, nicknameA);
  await alice.page.keyboard.type(nicknameA, { delay: 30 });

  await alice.page.evaluate(() => {
    const btns = document.querySelectorAll('flt-semantics [role="button"]');
    if (btns.length > 0) btns[btns.length - 1].click();
  });
  console.log(`[reg] Alice registered as "${nicknameA}"`);

  await bob.waitForSelector('[role="button"]', { timeout: 30000 });
  await bob.page.evaluate((nick) => {
    const inputs = document.querySelectorAll('flt-semantics [role="text"]');
    const input = inputs[inputs.length - 1];
    if (input) input.focus();
  }, nicknameB);
  await bob.page.keyboard.type(nicknameB, { delay: 30 });

  await bob.page.evaluate(() => {
    const btns = document.querySelectorAll('flt-semantics [role="button"]');
    if (btns.length > 0) btns[btns.length - 1].click();
  });
  console.log(`[reg] Bob registered as "${nicknameB}"`);

  await alice.waitForSelector('[aria-label="Chats"]', { timeout: 60000 });
  await bob.waitForSelector('[aria-label="Chats"]', { timeout: 60000 });
  console.log("[reg] both users completed registration");

  console.log("[reg] registration scenario passed");
}
