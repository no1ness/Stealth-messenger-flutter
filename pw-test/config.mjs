// Web URLs
const WEB_URL = process.env.STEALTH_WEB_URL || "http://127.0.0.1:58585";
const TEST_API_URL = process.env.STEALTH_TEST_API_URL || "http://127.0.0.1:9876";

// Appium configuration
const APPIUM_HOST = process.env.STEALTH_APPIUM_HOST || "127.0.0.1";
const APPIUM_PORT = process.env.STEALTH_APPIUM_PORT || "4723";

// PocketBase configuration
const POCKETBASE_URL = process.env.STEALTH_POCKETBASE_URL || "http://127.0.0.1:8090";

// Device UDIDs (for Appium tests)
const EMULATOR_UDID = process.env.STEALTH_EMULATOR_UDID || "emulator-5554";
const PHONE_UDID = process.env.STEALTH_PHONE_UDID;

// Chrome/Playwright configuration
const CHROME_BIN = process.env.CHROME_BIN;
const PW_CHANNEL = process.env.PW_CHANNEL;

// Headless mode: default true, set STEALTH_HEADLESS=false for headed debug
const HEADLESS = process.env.STEALTH_HEADLESS !== "false";

// Screenshot on failure
const SCREENSHOT_ON_FAILURE = process.env.STEALTH_SCREENSHOT_ON_FAILURE !== "false";

// Browser launch arguments
const LAUNCH_ARGS = [
  "--use-fake-ui-for-media-stream",
  "--use-fake-device-for-media-stream",
  "--no-sandbox",
];

// Viewport for mobile layout (bottom nav visible at < 960px)
const VIEWPORT = { width: 900, height: 800 };

// Context permissions
const CONTEXT_PERMISSIONS = [
  "microphone",
  "camera",
  "clipboard-read",
  "clipboard-write",
];

export {
  WEB_URL,
  TEST_API_URL,
  APPIUM_HOST,
  APPIUM_PORT,
  POCKETBASE_URL,
  EMULATOR_UDID,
  PHONE_UDID,
  CHROME_BIN,
  PW_CHANNEL,
  HEADLESS,
  SCREENSHOT_ON_FAILURE,
  LAUNCH_ARGS,
  VIEWPORT,
  CONTEXT_PERMISSIONS,
};
