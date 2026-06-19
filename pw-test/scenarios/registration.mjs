import { registerUser } from "../core/scenario-helpers.mjs";

export default async function registration({ alice, bob }) {
  const suffix = Date.now().toString(36);
  const nickA = "Alice_" + suffix;
  const nickB = "Bob_" + suffix;

  const t0 = Date.now();
  await Promise.all([registerUser(alice, nickA), registerUser(bob, nickB)]);
  console.log(`[reg] both users registered in ${Date.now() - t0}ms`);
}
