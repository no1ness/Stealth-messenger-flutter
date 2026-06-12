/// rtc_cleanup.pb.js — TTL for rtc_signaling (records older than 1 hour).
cronAdd("rtc_cleanup", "*/10 * * * *", function () {
  var cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  var result = $app
    .dao()
    .db()
    .newQuery("DELETE FROM rtc_signaling WHERE created < {:cutoff}")
    .bind({ cutoff: cutoff })
    .execute();
  if (result && result.rowsAffected && result.rowsAffected() > 0) {
    console.log(
      "[rtc_cleanup] Deleted " + result.rowsAffected() + " stale signaling records"
    );
  }
});
