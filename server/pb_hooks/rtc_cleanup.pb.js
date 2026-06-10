/// rtc_cleanup.pb.js
/// ------------------------------------------------------------------
/// Периодическая очистка коллекции `rtc_signaling`.
///
/// Запускается каждые 10 минут и удаляет записи старше 1 часа.
/// Индекс `idx_rtc_signaling_target_created` по полю `created`
/// делает DELETE-запрос дешёвым даже при большом объёме записей.
///
/// Совместимость: PocketBase JS hooks (goja, ES5-подмножество).
/// ------------------------------------------------------------------

cronAdd("rtc_cleanup", "*/10 * * * *", function () {
  var cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();

  var result = $app
    .dao()
    .db()
    .newQuery("DELETE FROM rtc_signaling WHERE created < {:cutoff}")
    .bind({ cutoff: cutoff })
    .execute();

  // Логируем количество удалённых записей для мониторинга.
  if (result && result.rowsAffected && result.rowsAffected() > 0) {
    console.log(
      "[rtc_cleanup] Deleted " +
        result.rowsAffected() +
        " stale signaling records (cutoff: " +
        cutoff +
        ")"
    );
  }
});
