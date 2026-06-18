export default async function callBasic({ alice, bob }) {
  await alice.waitForSelector("text=Chats", { timeout: 30000 });
  await bob.waitForSelector("text=Chats", { timeout: 30000 });

  const offerEv = await alice.events.waitForEvent("CallOfferCreated", { timeoutMs: 15000 });
  console.log(`[call] Alice created offer for room ${offerEv.roomId}`);

  const answerEv = await bob.events.waitForEvent("CallAnswered", { timeoutMs: 15000 });
  console.log(`[call] Bob answered room ${answerEv.roomId}`);

  await alice.events.waitForEvent("IceConnected", { timeoutMs: 20000 });
  await bob.events.waitForEvent("IceConnected", { timeoutMs: 20000 });
  console.log("[call] ICE connected for both peers");

  await alice.events.waitForEvent("CallEnded", { timeoutMs: 15000 });
  await bob.events.waitForEvent("CallEnded", { timeoutMs: 15000 });
  console.log("[call] call ended on both sides");

  console.log("[call] basic call scenario passed");
}
