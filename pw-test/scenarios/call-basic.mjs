export default async function callBasic({ alice, bob }) {
  await alice.waitForSelector('[aria-label="Chats"]', { timeout: 10000 });
  await bob.waitForSelector('[aria-label="Chats"]', { timeout: 10000 });

  const offerEv = await alice.events.waitForEvent("CallOfferCreated", { timeoutMs: 30000 });
  console.log(`[call] offer created for room ${offerEv.roomId}`);

  const answerEv = await bob.events.waitForEvent("CallAnswered", { timeoutMs: 30000 });
  console.log(`[call] Bob answered room ${answerEv.roomId}`);

  await Promise.all([
    alice.events.waitForEvent("IceConnected", { timeoutMs: 30000 }),
    bob.events.waitForEvent("IceConnected", { timeoutMs: 30000 }),
  ]);
  console.log("[call] ICE connected");

  await Promise.all([
    alice.events.waitForEvent("CallEnded", { timeoutMs: 30000 }),
    bob.events.waitForEvent("CallEnded", { timeoutMs: 30000 }),
  ]);
  console.log("[call] call ended on both sides");
}
