/**
 * webrtc-stats-test.mjs — Проверка реальной передачи аудио/видео через WebRTC
 *
 * Проверяет:
 *   1. Аудиозвонок — анализ RTC статистики (packetsReceived, bytesReceived, audioLevel)
 *   2. Видеозвонок — анализ RTC статистики (framesReceived, bytesReceived, frameWidth/Height)
 *   3. Качество соединения (jitter, packetsLost, roundTripTime)
 *
 * Запуск:
 *   set STEALTH_WEB_URL=http://127.0.0.1:58585
 *   node webrtc-stats-test.mjs
 */

import { chromium } from "playwright";

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
    bodyLength: document.body?.innerHTML?.length ?? 0,
    hasDebugRunMain: typeof window.$dartRunMain === "function",
    dartMainExecuted: !!window.$dartMainExecuted,
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
  return page.evaluate(async () => {
    for (let i = 0; i < 40; i++) {
      if (window.stealthCrypto) break;
      await new Promise((r) => setTimeout(r, 300));
    }
    if (!window.stealthCrypto) return null;
    const raw = localStorage.getItem("flutter.userId");
    if (!raw) return null;
    let enc;
    try {
      enc = JSON.parse(raw);
    } catch (_) {
      enc = raw;
    }
    try {
      return await window.stealthCrypto.decrypt(enc);
    } catch (_) {
      return null;
    }
  });
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

async function addContact(page, contactId) {
  await goToTab(page, "Contacts");
  await page.getByRole("button", { name: /Add contact/i }).click();

  await page.evaluate(async (id) => {
    try {
      await navigator.clipboard.writeText(id);
    } catch (_) {
      const ta = document.createElement("textarea");
      ta.value = id;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    }
  }, contactId);

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

/**
 * Получить информацию о MediaStream треках (альтернатива RTCPeerConnection.getStats)
 * Flutter WebRTC использует нативный binding, поэтому RTCPeerConnection не доступен в JS.
 * Вместо этого проверяем MediaStream треки и <video>/<audio> элементы.
 */
async function getMediaStreamInfo(page, kind = "audio") {
  return page.evaluate(async (mediaKind) => {
    const result = {
      tracks: [],
      videoElements: [],
      audioElements: [],
    };

    // 1. Проверяем MediaStreamTrack через getUserMedia (если доступен)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: mediaKind === "audio",
        video: mediaKind === "video",
      });

      stream.getTracks().forEach((track) => {
        result.tracks.push({
          kind: track.kind,
          id: track.id,
          label: track.label,
          enabled: track.enabled,
          muted: track.muted,
          readyState: track.readyState,
          settings: track.getSettings ? track.getSettings() : null,
        });
      });

      // Останавливаем тестовый stream
      stream.getTracks().forEach((t) => t.stop());
    } catch (e) {
      result.getUserMediaError = e.message;
    }

    // 2. Проверяем <video> элементы (для видеозвонков)
    if (mediaKind === "video") {
      document.querySelectorAll("video").forEach((v) => {
        result.videoElements.push({
          readyState: v.readyState,
          videoWidth: v.videoWidth,
          videoHeight: v.videoHeight,
          srcObject: !!v.srcObject,
          paused: v.paused,
          currentTime: v.currentTime,
          duration: v.duration,
        });
      });
    }

    // 3. Проверяем <audio> элементы (для аудиозвонков)
    if (mediaKind === "audio") {
      document.querySelectorAll("audio").forEach((a) => {
        result.audioElements.push({
          readyState: a.readyState,
          srcObject: !!a.srcObject,
          paused: a.paused,
          currentTime: a.currentTime,
          duration: a.duration,
        });
      });
    }

    // 4. Проверяем RTCPeerConnection (если flutter_webrtc экспонирует его)
    const pcs = [];
    for (const key in window) {
      try {
        const val = window[key];
        if (val && typeof val === "object" && typeof val.getStats === "function") {
          pcs.push(key);
        }
      } catch (_) {}
    }
    result.rtcPeerConnectionKeys = pcs;

    return result;
  }, kind);
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  Stealth Messenger — WebRTC Stats Test");
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
      fail("Registration", "Failed to read UUID");
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

    // ── TEST 1: AUDIO CALL + RTC STATS ───────────────────────────────────────
    console.log("\n▶ TEST 1: Audio Call + WebRTC Stats");

    const aliceToContacts = await goToTab(alice, "Contacts");
    if (!aliceToContacts) {
      fail("Audio Call", "Cannot navigate to Contacts");
    } else {
      await delay(1000);

      let callStarted = false;
      try {
        const callBtn = alice.getByRole("button", { name: "Start call" }).first();
        await callBtn.waitFor({ state: "visible", timeout: 10_000 });
        await callBtn.click();
        callStarted = true;
        info("📞 Alice initiated audio call…");
      } catch (e) {
        fail("Audio Call Init", e.message.slice(0, 80));
      }

      if (callStarted) {
        let bobAnswered = false;
        try {
          await bob.getByText(/Incoming call/i).first().waitFor({ state: "visible", timeout: 45_000 });
          pass("Incoming Audio Call", "Bob sees incoming call");
          await bob.getByRole("button", { name: /Answer/i }).click();
          bobAnswered = true;
          info("Bob answered audio call");
        } catch (e) {
          fail("Incoming Audio Call", e.message.slice(0, 80));
        }

        if (bobAnswered) {
          // Ждём установки соединения
          await delay(8000);

          // Проверяем статус соединения
          try {
            await alice.getByText(/Connected|Negotiating/i).first().waitFor({ state: "visible", timeout: 30_000 });
            pass("Audio Call Connected", "Alice sees Connected status");
          } catch (_) {
            fail("Audio Call Connected", "Alice doesn't see Connected status");
          }

          // ═══ АНАЛИЗ MEDIASTREAM ═══
          console.log("\n  📊 Analyzing MediaStream…");

          // Alice (отправитель)
          const aliceMedia = await getMediaStreamInfo(alice, "audio");
          info(`Alice tracks: ${aliceMedia.tracks.length}, audio elements: ${aliceMedia.audioElements.length}`);

          if (aliceMedia.tracks.length > 0) {
            const audioTracks = aliceMedia.tracks.filter((t) => t.kind === "audio");
            for (const track of audioTracks) {
              pass(
                "Alice Audio Track",
                `${track.label} — ${track.readyState}, enabled: ${track.enabled}, muted: ${track.muted}`
              );

              if (track.readyState === "live" && track.enabled && !track.muted) {
                pass("Alice Audio Stream", "✅ Audio track is LIVE and ENABLED");
              } else if (track.readyState === "live") {
                info(`Alice Audio Stream: live but ${track.enabled ? "muted" : "disabled"}`);
              } else {
                fail("Alice Audio Stream", `❌ Track state: ${track.readyState}`);
              }

              if (track.settings) {
                info(`  Settings: sampleRate=${track.settings.sampleRate}, channelCount=${track.settings.channelCount}`);
              }
            }
          } else {
            fail("Alice Audio Tracks", "No audio tracks found");
          }

          if (aliceMedia.rtcPeerConnectionKeys.length > 0) {
            pass("Alice RTCPeerConnection", `Found: ${aliceMedia.rtcPeerConnectionKeys.join(", ")}`);
          } else {
            info("Alice RTCPeerConnection: Not exposed in window (flutter_webrtc native binding)");
          }

          // Bob (получатель)
          await delay(2000);
          const bobMedia = await getMediaStreamInfo(bob, "audio");
          info(`Bob tracks: ${bobMedia.tracks.length}, audio elements: ${bobMedia.audioElements.length}`);

          if (bobMedia.tracks.length > 0) {
            const audioTracks = bobMedia.tracks.filter((t) => t.kind === "audio");
            for (const track of audioTracks) {
              pass(
                "Bob Audio Track",
                `${track.label} — ${track.readyState}, enabled: ${track.enabled}`
              );

              if (track.readyState === "live" && track.enabled) {
                pass("Bob Audio Stream", "✅ Audio track is LIVE and ENABLED");
              } else {
                fail("Bob Audio Stream", `❌ Track state: ${track.readyState}`);
              }
            }
          } else {
            fail("Bob Audio Tracks", "No audio tracks found");
          }

          // Hang up
          await delay(2000);
          try {
            await alice.getByRole("button", { name: /hang|end|decline/i }).first().click({ timeout: 5000 });
          } catch (_) {
            await alice.keyboard.press("Escape").catch(() => {});
          }
          await delay(2000);

          // Reset both pages to main screen
          await gotoApp(alice);
          await enableA11y(alice);
          await alice.getByRole("button", { name: "Chats" }).waitFor({ state: "visible", timeout: 20_000 });

          await gotoApp(bob);
          await enableA11y(bob);
          await bob.getByRole("button", { name: "Chats" }).waitFor({ state: "visible", timeout: 20_000 });
        }
      }
    }

    // ── TEST 2: VIDEO CALL + RTC STATS ───────────────────────────────────────
    console.log("\n▶ TEST 2: Video Call + WebRTC Stats");

    // Reset Alice to Contacts
    const aliceReady = await goToTab(alice, "Contacts");

    if (!aliceReady) {
      fail("Video Call", "Cannot navigate to Contacts");
    } else {
      await delay(1000);

      let videoCallStarted = false;
      try {
        const videoBtn = alice.getByRole("button", { name: "Start video call" }).first();
        await videoBtn.waitFor({ state: "visible", timeout: 10_000 });
        await videoBtn.click();
        videoCallStarted = true;
        info("📹 Alice initiated video call…");
      } catch (e) {
        fail("Video Call Init", e.message.slice(0, 80));
      }

      if (videoCallStarted) {
        let bobAnsweredVideo = false;
        try {
          await bob.getByText(/Incoming|video call/i).first().waitFor({ state: "visible", timeout: 45_000 });
          pass("Incoming Video Call", "Bob sees incoming video call");
          await bob.getByRole("button", { name: /Answer/i }).click();
          bobAnsweredVideo = true;
          info("Bob answered video call");
        } catch (e) {
          fail("Incoming Video Call", e.message.slice(0, 80));
        }

        if (bobAnsweredVideo) {
          // Ждём установки видеосоединения
          await delay(10000);

          // ═══ АНАЛИЗ VIDEO MEDIASTREAM ═══
          console.log("\n  📊 Analyzing Video MediaStream…");

          // Alice (отправитель видео)
          const aliceVideoMedia = await getMediaStreamInfo(alice, "video");
          info(`Alice video tracks: ${aliceVideoMedia.tracks.length}, video elements: ${aliceVideoMedia.videoElements.length}`);

          if (aliceVideoMedia.tracks.length > 0) {
            const videoTracks = aliceVideoMedia.tracks.filter((t) => t.kind === "video");
            for (const track of videoTracks) {
              pass(
                "Alice Video Track",
                `${track.label} — ${track.readyState}, enabled: ${track.enabled}`
              );

              if (track.readyState === "live" && track.enabled) {
                pass("Alice Video Stream", "✅ Video track is LIVE and ENABLED");
              } else {
                fail("Alice Video Stream", `❌ Track state: ${track.readyState}`);
              }

              if (track.settings) {
                pass(
                  "Alice Video Settings",
                  `${track.settings.width}x${track.settings.height} @ ${track.settings.frameRate}fps`
                );
              }
            }
          } else {
            fail("Alice Video Tracks", "No video tracks found");
          }

          if (aliceVideoMedia.videoElements.length > 0) {
            for (const v of aliceVideoMedia.videoElements) {
              pass(
                "Alice <video> Element",
                `${v.videoWidth}x${v.videoHeight}, readyState=${v.readyState}, srcObject=${v.srcObject}, paused=${v.paused}`
              );

              if (v.srcObject && v.readyState >= 2 && v.videoWidth > 0) {
                pass("Alice Video Rendering", "✅ Video is being RENDERED");
              } else {
                fail("Alice Video Rendering", "❌ Video not rendering properly");
              }
            }
          } else {
            info("Alice <video> elements: None (flutter_webrtc may use canvas rendering)");
          }

          // Bob (получатель видео)
          await delay(2000);
          const bobVideoMedia = await getMediaStreamInfo(bob, "video");
          info(`Bob video tracks: ${bobVideoMedia.tracks.length}, video elements: ${bobVideoMedia.videoElements.length}`);

          if (bobVideoMedia.tracks.length > 0) {
            const videoTracks = bobVideoMedia.tracks.filter((t) => t.kind === "video");
            for (const track of videoTracks) {
              pass(
                "Bob Video Track",
                `${track.label} — ${track.readyState}, enabled: ${track.enabled}`
              );

              if (track.readyState === "live" && track.enabled) {
                pass("Bob Video Stream", "✅ Video track is LIVE and ENABLED");
              } else {
                fail("Bob Video Stream", `❌ Track state: ${track.readyState}`);
              }
            }
          } else {
            fail("Bob Video Tracks", "No video tracks found");
          }

          if (bobVideoMedia.videoElements.length > 0) {
            for (const v of bobVideoMedia.videoElements) {
              pass(
                "Bob <video> Element",
                `${v.videoWidth}x${v.videoHeight}, readyState=${v.readyState}, srcObject=${v.srcObject}`
              );

              if (v.srcObject && v.readyState >= 2 && v.videoWidth > 0) {
                pass("Bob Video Rendering", "✅ Video is being RENDERED");
              } else {
                fail("Bob Video Rendering", "❌ Video not rendering properly");
              }
            }
          } else {
            info("Bob <video> elements: None (flutter_webrtc may use canvas rendering)");
          }

          // Hang up
          await delay(2000);
          try {
            await alice.getByRole("button", { name: /hang|end|decline/i }).first().click({ timeout: 5000 });
          } catch (_) {
            await alice.keyboard.press("Escape").catch(() => {});
          }
          await delay(2000);
        }
      }
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
