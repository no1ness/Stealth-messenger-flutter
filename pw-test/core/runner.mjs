import { Client } from "./client.mjs";
import { WEB_URL } from "../config.mjs";

export async function runScenario(scenarioFn) {
  const clientA = new Client("Alice");
  const clientB = new Client("Bob");
  try {
    await clientA.launch();
    await clientB.launch();
    const env = {
      alice: clientA,
      bob: clientB,
      url: WEB_URL,
    };
    await scenarioFn(env);
  } finally {
    await clientA.close();
    await clientB.close();
  }
}
