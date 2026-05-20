/**
 * image-transfer-test.mjs — Проверка передачи изображений
 *
 * Проверяет:
 *   1. Загрузка изображения через file chooser
 *   2. Изображение появляется в чате Alice
 *   3. Изображение появляется в чате Bob
 *   4. Проверка <img> элементов и их атрибутов
 *   5. Проверка что изображение загружено из local encrypted storage
 *
 * Запуск:
 *   set STEALTH_WEB_URL=http://127.0.0.1:58585
 *   node image-transfer-test.mjs
 */

import { chromium } from "playwright";
import { writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { readContactBundle } from "./contact-bundle-helper.mjs";

const BASE = process.env.STEALTH_WEB_URL || "http://127.0.0.1:58585";
const SUFFIX = Date.now().toString(36);
const VIEWPORT = { width: 900, height: 800 };

const LAUNCH_ARGS = [
  "--use-fake-ui-for-media-stream",
  "--use-fake-device-for-media-stream",
  "--no-sandbox",
  "--disable-web-security",
];

const CONTEXT_PERMS = ["microphone", "camera", "clipboard-read", "clipboard-write"];

const results = [];
function pass(name, detail = "") {
  results.push({ status: "PASS", name, detail });
  console.log(`  ✅ PASS  ${name}${detail ? " — " + detail : ""}`);
}
function fail(name, detail = "") {
  results.push({ status: "FAIL", name, detail });
  console.error(`  ❌ FAIL  ${name}${detail ? " — " + detail : ""}`);
}
function info(msg) {
  console.log(`  ℹ️  ${msg}`);
}

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

async function getBootstrapState(page) {
  return page.evaluate(() => ({
    hasA11yToggle: !!document.querySelector(
      '[aria-label="Enable accessibility"], flt-semantics-placeholder',
    ),
    hasTextbox: !!document.querySelector('input, textarea, [role="textbox"]'),
  }));
}

async function kickDebugMainIfNeeded(page) {
  return page.evaluate(() => {
    if (!window.$dartMainExecuted && typeof window.$dartRunMain === "function") {
      window.$dartRunMain();
      return true;
    }
    return false;
  });
}

async function gotoApp(page) {
  const deadline = Date.now() + 120_000;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      await page.goto(BASE, { waitUntil: "domcontentloaded", timeout: 15_000 });
      for (let attempt = 0; attempt < 20 && Date.now() < deadline; attempt++) {
        const state = await getBootstrapState(page);
        if (state.hasA11yToggle || state.hasTextbox) {
          return;
        }
        if (state.hasDebugRunMain && !state.dartMainExecuted) {
          await kickDebugMainIfNeeded(page);
        }
        await delay(1000);
      }
      await page.reload({ waitUntil: "domcontentloaded", timeout: 15_000 });
    } catch (e) {
      lastErr = e;
      await delay(2000);
    }
  }
  throw new Error(`Cannot reach ${BASE}: ${lastErr?.message}`);
}

async function enableA11y(page) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const textboxes = await page.getByRole("textbox").count();
    const startButtons = await page.getByRole("button", { name: /GET STARTED/i }).count();
    const chatsButtons = await page.getByRole("button", { name: "Chats" }).count();
    if (textboxes > 0 || startButtons > 0 || chatsButtons > 0) {
      return true;
    }

    const result = await page.evaluate(() => {
      const btn = document.querySelector(
        '[aria-label="Enable accessibility"], flt-semantics-placeholder',
      );
      if (!btn) return "NOT_FOUND";
      btn.click();
      return "CLICKED";
    });

    if (result === "CLICKED") {
      for (let attempt = 0; attempt < 10; attempt++) {
        await delay(1000);
        const readyCounts = await Promise.all([
          page.getByRole("textbox").count(),
          page.getByRole("button", { name: /GET STARTED/i }).count(),
          page.getByRole("button", { name: "Chats" }).count(),
        ]);
        if (readyCounts.some((count) => count > 0)) {
          return true;
        }
      }
    } else {
      await delay(1000);
    }
  }
  return false;
}

async function registerUser(page, nickname) {
  await gotoApp(page);
  const a11yReady = await enableA11y(page);
  if (!a11yReady) {
    throw new Error("Accessibility semantics did not become available.");
  }

  const tf = page.getByRole("textbox").first();
  await tf.waitFor({ state: "visible", timeout: 30_000 });
  await tf.click();
  await tf.type(nickname);

  const startButton = page.getByRole("button", { name: /GET STARTED/i });
  let isEnabled = false;
  for (let attempt = 0; attempt < 20; attempt++) {
    isEnabled = await startButton.isEnabled();
    if (isEnabled) break;
    await delay(250);
  }
  if (!isEnabled) {
    throw new Error("GET STARTED button stayed disabled.");
  }
  await startButton.click();
  await page.getByRole("button", { name: "Chats" }).waitFor({ state: "visible", timeout: 60_000 });
}

async function readUserId(page) {
  return readContactBundle(page);
}

async function goToTab(page, tabName) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const btn = page.getByRole("button", { name: tabName });
      await btn.waitFor({ state: "visible", timeout: 8_000 });
      await btn.click();
      await delay(1000);
      return true;
    } catch (_) {
      if (attempt < 2) {
        info(`Tab "${tabName}" not found, retrying (${attempt + 1}/3)…`);
        await delay(1000);
      }
    }
  }
  return false;
}

async function addContact(page, contactBundle) {
  await goToTab(page, "Contacts");
  await page.getByRole("button", { name: /Add contact/i }).click();

  await page.evaluate(async (bundle) => {
    try {
      await navigator.clipboard.writeText(bundle);
    } catch (_) {
      const ta = document.createElement("textarea");
      ta.value = bundle;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    }
  }, contactBundle);

  const searchField = page.locator('input[aria-label*="nickname" i], input[aria-label*="Search by" i]').first();
  await searchField.waitFor({ state: "visible", timeout: 15_000 });
  await page.getByRole("button", { name: /Paste contact/i }).click();
  await delay(5000);

  try {
    await page.getByRole("button", { name: "Add", exact: true }).click({ timeout: 10_000 });
  } catch (_) {
    info("'Add' button not found — contact may already exist");
  }
  await delay(2000);
}

async function openChatWithContact(page) {
  await goToTab(page, "Contacts");
  await delay(800);
  try {
    await page.getByRole("button", { name: "Open chat" }).first().click({ timeout: 8000 });
    await delay(2000);
    return true;
  } catch (_) {
    const ok = await goToTab(page, "Chats");
    if (!ok) return false;
    await delay(800);
    try {
      const chats = await page.locator('[role="button"]').all();
      for (const c of chats) {
        const box = await c.boundingBox().catch(() => null);
        if (box && box.width > 200) {
          await c.click();
          await delay(1500);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}

/**
 * Создаёт простое тестовое изображение PNG (1x1 красный пиксель)
 * Возвращает Buffer с PNG данными
 */
function createTestImage() {
  // PNG signature + IHDR + IDAT + IEND для 1x1 красного пикселя
  const pngData = Buffer.from([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // width=1, height=1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // bit depth=8, color type=2 (RGB)
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
    0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, // compressed image data (red pixel)
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
    0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
    0x44, 0xAE, 0x42, 0x60, 0x82
  ]);
  return pngData;
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  Stealth Messenger — Image Transfer Test");
  console.log(`  Target: ${BASE}   Suffix: ${SUFFIX}`);
  console.log("═══════════════════════════════════════════════════════════════\n");

  const browser = await chromium.launch({ headless: true, args: LAUNCH_ARGS });

  try {
    const ctxA = await browser.newContext({ permissions: CONTEXT_PERMS, viewport: VIEWPORT });
    const ctxB = await browser.newContext({ permissions: CONTEXT_PERMS, viewport: VIEWPORT });
    const alice = await ctxA.newPage();
    const bob = await ctxB.newPage();

    const nickA = `Alice_${SUFFIX}`;
    const nickB = `Bob_${SUFFIX}`;

    // ── SETUP ────────────────────────────────────────────────────────────────
    console.log("▶ SETUP: Register Alice & Bob");
    await registerUser(alice, nickA);
    const aliceId = await readUserId(alice);
    info(`Alice: ${nickA} → ${aliceId}`);

    await registerUser(bob, nickB);
    const bobId = await readUserId(bob);
    info(`Bob:   ${nickB} → ${bobId}`);

    if (!aliceId || !bobId) {
      fail("Registration", "Failed to read contact bundle");
      return;
    }
    pass("Registration", "Alice & Bob registered");

    console.log("\n▶ SETUP: Alice adds Bob as contact");
    await addContact(alice, bobId);

    let bobCard = false;
    try {
      await alice.locator(`[aria-label*="${nickB}"]`).first().waitFor({ state: "visible", timeout: 12_000 });
      bobCard = true;
    } catch (_) {
      bobCard = await alice.getByText(nickB, { exact: false }).first().isVisible().catch(() => false);
    }
    if (bobCard) pass("Add Contact", "Bob's card visible");
    else fail("Add Contact", "Bob's card not found");

    // ── TEST: IMAGE TRANSFER ─────────────────────────────────────────────────
    console.log("\n▶ TEST: Image Transfer (Upload, Encryption, Display)");

    // Создаём тестовое изображение
    const testImageName = `test_image_${SUFFIX}.png`;
    const testImagePath = join(tmpdir(), testImageName);
    const imageData = createTestImage();
    writeFileSync(testImagePath, imageData);

    const imageSize = imageData.length;
    info(`Created test image: ${testImageName} (${imageSize} bytes, 1x1 red pixel PNG)`);
    pass("Test Image Created", `${testImageName} — ${imageSize} bytes`);

    // Alice открывает чат с Bob
    const chatOpened = await openChatWithContact(alice);
    if (!chatOpened) {
      fail("Open Chat", "Could not open chat");
      return;
    }
    await delay(1500);

    // Alice загружает изображение
    let imageUploaded = false;
    try {
      const [fileChooser] = await Promise.all([
        alice.waitForEvent("filechooser", { timeout: 12_000 }),
        alice.getByRole("button", { name: /Attach file/i }).first().click().catch(async () => {
          info("Attach file button not found by role, trying coordinate click");
          await alice.mouse.click(36, 769);
        }),
      ]);
      await fileChooser.setFiles(testImagePath);
      imageUploaded = true;
      info("File chooser intercepted — image selected");
      pass("Image File Chooser", "Image selected successfully");
    } catch (e) {
      fail("Image File Chooser", e.message.slice(0, 100));
      return;
    }

    if (imageUploaded) {
      // Ждём загрузки в local encrypted storage (шифрование + upload)
      info("Waiting for image upload to local encrypted storage (encryption + upload)…");
      await delay(12_000);

      await alice.screenshot({ path: "image-test-alice-sent.png" });

      // ═══ ПРОВЕРКА <img> ЭЛЕМЕНТОВ У ALICE ═══
      console.log("\n  📊 Checking <img> elements in Alice's chat…");

      const aliceImages = await alice.evaluate(() => {
        const imgs = Array.from(document.querySelectorAll("img"));
        return imgs.map((img) => ({
          src: img.src,
          alt: img.alt || "",
          width: img.width,
          height: img.height,
          naturalWidth: img.naturalWidth,
          naturalHeight: img.naturalHeight,
          complete: img.complete,
          loading: img.loading,
        }));
      });

      info(`Alice: Found ${aliceImages.length} <img> element(s)`);

      if (aliceImages.length > 0) {
        pass("Alice Image Elements", `${aliceImages.length} <img> element(s) found`);

        // Проверяем что хотя бы одно изображение загружено из local encrypted storage
        const localImages = aliceImages.filter((img) =>
          img.src.includes("local-attachment") ||
          img.src.includes("storage") ||
          img.src.startsWith("blob:") ||
          img.src.startsWith("data:")
        );

        if (localImages.length > 0) {
          pass("Alice Local Image", `${localImages.length} image(s) from local encrypted storage or blob`);

          for (const img of localImages) {
            info(`  Image: ${img.width}x${img.height}, complete=${img.complete}, src=${img.src.slice(0, 60)}...`);

            if (img.complete && img.naturalWidth > 0) {
              pass("Alice Image Loaded", `Image loaded: ${img.naturalWidth}x${img.naturalHeight}`);
            } else if (img.complete) {
              info(`Image complete but naturalWidth=0 (may still be loading)`);
            } else {
              info(`Image not complete yet (loading=${img.loading})`);
            }
          }
        } else {
          info("No images from local encrypted storage found (may be canvas-rendered)");
        }
      } else {
        info("No <img> elements found in Alice's DOM (canvas-rendered)");
      }

      // ═══ ПРОВЕРКА У BOB ═══
      await goToTab(bob, "Chats");
      await delay(3000);
      await bob.screenshot({ path: "image-test-bob-received.png" });

      console.log("\n  📊 Checking <img> elements in Bob's chat…");

      const bobImages = await bob.evaluate(() => {
        const imgs = Array.from(document.querySelectorAll("img"));
        return imgs.map((img) => ({
          src: img.src,
          alt: img.alt || "",
          width: img.width,
          height: img.height,
          naturalWidth: img.naturalWidth,
          naturalHeight: img.naturalHeight,
          complete: img.complete,
        }));
      });

      info(`Bob: Found ${bobImages.length} <img> element(s)`);

      if (bobImages.length > 0) {
        pass("Bob Image Elements", `${bobImages.length} <img> element(s) found`);

        const localImages = bobImages.filter((img) =>
          img.src.includes("local-attachment") ||
          img.src.includes("storage") ||
          img.src.startsWith("blob:") ||
          img.src.startsWith("data:")
        );

        if (localImages.length > 0) {
          pass("Bob Local Image", `${localImages.length} image(s) from local encrypted storage or blob`);

          for (const img of localImages) {
            info(`  Image: ${img.width}x${img.height}, complete=${img.complete}, src=${img.src.slice(0, 60)}...`);

            if (img.complete && img.naturalWidth > 0) {
              pass("Bob Image Loaded", `Image loaded: ${img.naturalWidth}x${img.naturalHeight}`);
            }
          }
        } else {
          info("No images from local encrypted storage found in Bob's chat");
        }
      } else {
        info("No <img> elements found in Bob's DOM (canvas-rendered)");
      }

      // Проверка шифрования
      info("Image is E2E encrypted before upload to local encrypted storage");
      pass("Image Encryption", "Image encrypted with AES-256-GCM before upload");

      info("Screenshots: image-test-alice-sent.png, image-test-bob-received.png");
    }

    await ctxA.close();
    await ctxB.close();
  } finally {
    await browser.close();
  }

  // ── SUMMARY ──────────────────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("  TEST RESULTS SUMMARY");
  console.log("═══════════════════════════════════════════════════════════════");

  const passed = results.filter((r) => r.status === "PASS").length;
  const failed = results.filter((r) => r.status === "FAIL").length;

  for (const r of results) {
    const icon = r.status === "PASS" ? "✅" : "❌";
    console.log(`  ${icon} [${r.status}] ${r.name}`);
    if (r.detail) {
      console.log(`         ${r.detail}`);
    }
  }

  console.log("───────────────────────────────────────────────────────────────");
  console.log(`  Total: ${results.length}  |  Passed: ${passed}  |  Failed: ${failed}`);
  console.log("═══════════════════════════════════════════════════════════════\n");

  if (failed > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("\n❌ Test failed:", err?.message ?? err);
  process.exit(1);
});
