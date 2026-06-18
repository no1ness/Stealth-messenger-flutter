export default async function registration({ alice, bob }) {
  await alice.waitForSelector('[aria-label="Register"]', { timeout: 30000 });
  const regScreen = await alice.page.$('[aria-label="Register"]');
  if (regScreen) {
    console.log("[reg] registration screen visible for Alice");
  }

  await alice.waitForSelector("text=Chats", { timeout: 60000 });
  await bob.waitForSelector("text=Chats", { timeout: 60000 });
  console.log("[reg] both users completed registration");

  const contactEv = await alice.events.waitForEvent("ContactAdded", { timeoutMs: 15000 });
  console.log(`[reg] Alice added contact ${contactEv.userId}`);

  console.log("[reg] registration + bundle exchange scenario passed");
}
