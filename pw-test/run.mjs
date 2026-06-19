import { runScenario, runSuite } from "./core/runner.mjs";

const SCENARIOS = {
  registration: () => import("./scenarios/registration.mjs"),
  call: () => import("./scenarios/call-basic.mjs"),
  chat: () => import("./scenarios/chat-basic.mjs"),
};

const SUITE = "suite";

const args = process.argv.slice(2);
const mode = args[0];
const startServer = args.includes("--server");

if (mode === SUITE) {
  const results = await runSuite([
    { name: "call", fn: (await import("./scenarios/call-basic.mjs")).default },
    { name: "chat", fn: (await import("./scenarios/chat-basic.mjs")).default },
  ], { startServer });
  process.exit(results.passed ? 0 : 1);
}

if (!mode || !SCENARIOS[mode]) {
  console.error(`Usage: node run.mjs <scenario|suite> [--server]`);
  console.error(`Scenarios: ${Object.keys(SCENARIOS).join(", ")}`);
  console.error(`Suite: suite`);
  process.exit(1);
}

const { default: scenarioFn } = await SCENARIOS[mode]();
const result = await runScenario(scenarioFn, { startServer });
process.exit(result.passed ? 0 : 1);
