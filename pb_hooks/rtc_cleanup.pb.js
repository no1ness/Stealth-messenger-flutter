/// <reference path="../pb_data/types.d.ts" />

// rtc_signaling TTL cleanup
// =========================
//
// Drops every `rtc_signaling` record older than 24 hours, every hour.
//
// Why this hook exists
// --------------------
//
// `rtc_signaling` is a transient transport: a WebRTC offer/answer/ICE
// exchange completes in seconds, and once both peers are connected the
// stored row has no purpose. Leaving rows around forever lets the
// PocketBase admin (or anyone with read access) reconstruct a
// long-tail call graph — who called whom, when, from which device.
// The metadata `creator`/`target`/`payload.creatorUuid` is enough to
// derive that even without decrypting SDP.
//
// 24h is the documented retention window in
// `docs/POCKETBASE_SETUP.md`. The window is intentionally generous so
// genuinely slow handshakes (PWA waking from background, cold mobile
// data, retries through TURN) still see the prior step, but anything
// older than a day is unambiguously stale.
//
// Deployment
// ----------
//
// 1. Copy this file to `<pocketbase install>/pb_hooks/rtc_cleanup.pb.js`
//    on the signaling host. PocketBase auto-loads every `*.pb.js`
//    file under `pb_hooks/` on start.
// 2. Restart the PocketBase server (`systemctl restart pocketbase` or
//    `docker compose restart pocketbase`).
// 3. Verify the cron is registered: in the admin UI go to Logs and
//    filter for `[rtcSignalingCleanup]`. The first sweep runs at the
//    top of the next hour.
//
// To change the retention window, edit the `RETENTION_MS` constant
// and redeploy. Keep it strictly greater than the longest expected
// handshake (a few minutes in the worst case).

cronAdd("rtcSignalingCleanup", "0 * * * *", () => {
  const RETENTION_MS = 24 * 60 * 60 * 1000; // 24h
  const cutoff = new Date(Date.now() - RETENTION_MS).toISOString();

  let deleted = 0;
  let scanned = 0;
  try {
    const records = $app.dao().findRecordsByExpr(
      "rtc_signaling",
      $dbx.exp("created < {:cutoff}", { cutoff: cutoff })
    );
    scanned = records.length;
    for (const record of records) {
      $app.dao().deleteRecord(record);
      deleted++;
    }
    console.log(
      `[rtcSignalingCleanup] swept ${scanned} stale rows, deleted ${deleted}, ` +
      `cutoff=${cutoff}`
    );
  } catch (err) {
    // Never throw from a cron callback — that would kill the schedule
    // for the rest of the PocketBase process lifetime. Log loudly so
    // the operator can investigate via `pocketbase logs`.
    console.error(
      `[rtcSignalingCleanup] failed after scanning=${scanned} ` +
      `deleted=${deleted} cutoff=${cutoff}: ${err}`
    );
  }
});
