export async function attachBridge(page, eventBus) {
  await page.exposeFunction("__stealthEmit", (event) => {
    eventBus.push(event);
  });

  await page.route("**/api/collections/rtc_signaling/**", async (route) => {
    const req = route.request();
    if (req.method() === "POST") {
      try {
        const body = JSON.parse(req.postData());
        switch (body.type) {
          case "offer":
            eventBus.push({
              type: "CallOfferCreated",
              roomId: body.roomId,
              targetUserId: body.target,
            });
            break;
          case "answer":
            eventBus.push({
              type: "CallAnswered",
              roomId: body.roomId,
              fromUserId: body.creator,
            });
            break;
          case "hangup":
            eventBus.push({
              type: "CallEnded",
              chatId: body.roomId,
            });
            break;
        }
      } catch {}
    }
    await route.continue();
  });

  await page.route("**/api/collections/user_profiles/**", async (route) => {
    const req = route.request();
    if (req.method() === "POST") {
      try {
        const body = JSON.parse(req.postData());
        if (body.userId) {
          eventBus.push({
            type: "ContactAdded",
            userId: body.userId,
          });
        }
      } catch {}
    }
    await route.continue();
  });

  await page.addInitScript(() => {
    if (typeof RTCDataChannel !== "undefined") {
      const origSend = RTCDataChannel.prototype.send;
      RTCDataChannel.prototype.send = function (data) {
        try {
          if (typeof data === "string") {
            const parsed = JSON.parse(data);
            if (parsed.content || parsed.message_type) {
              window.__stealthEmit?.({
                type: "MessageSent",
                chatId: parsed.chat_id || "",
                text: parsed.content || "",
              });
            }
          }
        } catch {}
        return origSend.call(this, data);
      };
    }

    if (typeof RTCDataChannel !== "undefined") {
      const origSet =
        Object.getOwnPropertyDescriptor(
          RTCDataChannel.prototype,
          "onmessage",
        )?.set;

      if (origSet) {
        let _handler = null;
        Object.defineProperty(RTCDataChannel.prototype, "onmessage", {
          get() {
            return _handler;
          },
          set(fn) {
            _handler = fn;
            origSet.call(this, function (event) {
              try {
                if (typeof event.data === "string") {
                  const parsed = JSON.parse(event.data);
                  if (parsed.content || parsed.message_type) {
                    window.__stealthEmit?.({
                      type: "MessageReceived",
                      chatId: parsed.chat_id || "",
                      fromUserId: parsed.sender_id || "",
                      text: parsed.content || "",
                    });
                  }
                }
              } catch {}
              if (fn) fn.call(this, event);
            });
          },
          configurable: true,
        });
      }
    }
  });

  page.on("console", (msg) => {
    const text = msg.text();
    const match = text.match(/\[test-controller\] emit (\w+)/);
    if (match) {
      const eventType = match[1];
      if (!["TestErrorEvent"].includes(eventType)) {
        eventBus.push({ type: eventType, _fromConsole: true });
      }
    }
  });

  page.on("crash", () => {
    eventBus.push({ type: "Error", message: "Page crashed" });
  });
}
