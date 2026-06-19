import { runScenario } from "./core/runner.mjs";

const SCENARIOS = {
  registration: () => import("./scenarios/registration.mjs"),
  call: () => import("./scenarios/call-basic.mjs"),
  chat: () => import("./scenarios/chat-basic.mjs"),
};

const args = process.argv.slice(2);
const scenarioName = args[0];
const startServer = args.includes("--server");

if (!scenarioName || !SCENARIOS[scenarioName]) {
  console.error(`Usage: node run.mjs <scenario> [--server]`);
  console.error(`Available: ${Object.keys(SCENARIOS).join(", ")}`);
  process.exit(1);
}

const { default: scenarioFn } = await SCENARIOS[scenarioName]();
const result = await runScenario(scenarioFn, { startServer });
process.exit(result.passed ? 0 : 1);
