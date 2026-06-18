export default async function chatBasic({ alice, bob }) {
  await alice.waitForSelector("text=Chats", { timeout: 30000 });
  await bob.waitForSelector("text=Chats", { timeout: 30000 });

  const aliceEvent = alice.waitForEvent("MessageReceived", { timeoutMs: 20000 });
  const bobEvent = bob.waitForEvent("MessageReceived", { timeoutMs: 20000 });

  await alice.events.waitForEvent("MessageSent", { timeoutMs: 10000 });
  const msg = await aliceEvent;
  console.log(`[chat] Alice received message: ${msg.text}`);

  await bob.events.waitForEvent("MessageSent", { timeoutMs: 10000 });
  const msg2 = await bobEvent;
  console.log(`[chat] Bob received message: ${msg2.text}`);

  console.log("[chat] basic chat scenario passed");
}
