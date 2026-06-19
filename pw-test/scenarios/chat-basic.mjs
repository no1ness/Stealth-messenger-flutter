export default async function chatBasic({ alice, bob }) {
  await alice.waitForSelector('[aria-label="Chats"]', { timeout: 10000 });
  await bob.waitForSelector('[aria-label="Chats"]', { timeout: 10000 });

  const [sent, received] = await Promise.all([
    alice.events.waitForEvent("MessageSent", { timeoutMs: 30000 }),
    bob.events.waitForEvent("MessageReceived", { timeoutMs: 30000 }),
  ]);
  console.log(`[chat] sent: ${sent.text}, received: ${received.text}`);
}
