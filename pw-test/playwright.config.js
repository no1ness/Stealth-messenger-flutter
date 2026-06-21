import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  timeout: 120_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  retries: 0,
  reporter: [["list"], ["json", { outputFile: "test-results.json" }]],
  use: {
    baseURL: process.env.STEALTH_WEB_URL || "http://127.0.0.1:58585",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    viewport: { width: 900, height: 800 },
    permissions: ["microphone", "camera", "clipboard-read", "clipboard-write"],
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        launchOptions: {
          args: [
            "--use-fake-ui-for-media-stream",
            "--use-fake-device-for-media-stream",
            "--no-sandbox",
          ],
          headless: process.env.STEALTH_HEADLESS !== "false",
        },
      },
    },
  ],
});
