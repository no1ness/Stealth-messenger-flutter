onRecordAfterCreate(function (e) {
  var record = e.record;
  var targetId = record.getString("target");
  if (!targetId) {
    return;
  }
  // PB 0.23: query instead of findRecordById to avoid logged stack traces
  var rows = $app.dao().db()
    .newQuery("SELECT id FROM users WHERE id={:id} LIMIT 1")
    .bind({ id: targetId })
    .execute();
  if (!rows || !rows.length) {
    return;
  }
}, "rtc_signaling");
