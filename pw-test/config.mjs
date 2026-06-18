const WEB_URL = process.env.STEALTH_WEB_URL || "http://127.0.0.1:57575";
const TEST_API_URL = process.env.STEALTH_TEST_API_URL || "http://127.0.0.1:9876";

const LAUNCH_ARGS = [
  "--use-fake-ui-for-media-stream",
  "--use-fake-device-for-media-stream",
];

export { WEB_URL, TEST_API_URL, LAUNCH_ARGS };
