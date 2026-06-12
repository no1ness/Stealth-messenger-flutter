/// push_dispatcher.pb.js — optional UnifiedPush (safe if pushSubscription unset).
onRecordAfterCreate(function (e) {
  var record = e.record;
  var targetId = record.getString("target");
  if (!targetId) {
    e.next();
    return;
  }
  try {
    $app.dao().findRecordById("users", targetId);
  } catch (err) {
    e.next();
    return;
  }
  e.next();
}, "rtc_signaling");
