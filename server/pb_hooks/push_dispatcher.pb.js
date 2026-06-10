/// push_dispatcher.pb.js
/// ------------------------------------------------------------------
/// UnifiedPush диспетчер для входящих сигналов WebRTC.
///
/// Срабатывает после создания записи в коллекции `rtc_signaling`.
/// Находит получателя (`target`) в коллекции `users`, считывает его
/// поле `pushSubscription` (JSON) и отправляет HTTP POST на указанный
/// endpoint (ntfy.sh или self-hosted ntfy).
///
/// Использует onRecordAfterCreate (не *Request), чтобы push-логика не
/// влияла на HTTP-ответ create API и realtime-доставку.
///
/// Совместимость: PocketBase JS hooks (goja, ES5-подмножество).
/// ------------------------------------------------------------------

onRecordAfterCreate(function (e) {
  var record = e.record;

  var targetId = record.getString("target");
  var signalType = record.getString("type");
  var roomId = record.getString("roomId");

  if (!targetId) {
    e.next();
    return;
  }

  var targetUser;
  try {
    targetUser = $app.dao().findRecordById("users", targetId);
  } catch (err) {
    console.log(
      "[push_dispatcher] Target user not found: " + targetId + ", skipping push"
    );
    e.next();
    return;
  }

  var subscriptionRaw = targetUser.get("pushSubscription");
  if (!subscriptionRaw) {
    e.next();
    return;
  }

  var subscription;
  if (typeof subscriptionRaw === "string") {
    try {
      subscription = JSON.parse(subscriptionRaw);
    } catch (parseErr) {
      console.log(
        "[push_dispatcher] Failed to parse pushSubscription for user " +
          targetId +
          ": " +
          parseErr
      );
      e.next();
      return;
    }
  } else {
    subscription = subscriptionRaw;
  }

  if (!subscription || !subscription.endpoint || subscription.enabled === false) {
    e.next();
    return;
  }

  var pushBody = JSON.stringify({
    type: signalType,
    roomId: roomId,
    timestamp: new Date().toISOString()
  });

  var priority = "default";
  if (signalType === "offer" || signalType === "hangup") {
    priority = "high";
  }

  var title = "Stealth";
  if (signalType === "offer") {
    title = "Входящий звонок";
  } else if (signalType === "hangup") {
    title = "Звонок завершён";
  }

  try {
    $http.send({
      url: subscription.endpoint,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Title": title,
        "Priority": priority,
        "Tags": "phone"
      },
      body: pushBody,
      timeout: 10
    });

    console.log(
      "[push_dispatcher] Push sent to " +
        targetId +
        " (type: " +
        signalType +
        ", room: " +
        roomId +
        ")"
    );
  } catch (httpErr) {
    console.log(
      "[push_dispatcher] Failed to send push to " +
        targetId +
        ": " +
        httpErr
    );
  }

  e.next();
}, "rtc_signaling");
