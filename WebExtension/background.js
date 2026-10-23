// Relays requests to the native app extension (SafariWebExtensionHandler.swift),
// which owns the allowlist and the main on/off switch shared with the app.

// Safari ignores the application ID and always talks to the containing app.
const native = (message) => browser.runtime.sendNativeMessage("application.id", message);

// Every page asks whether uKivi is switched off; cache the answer briefly.
let globalState = { paused: false, checkedAt: 0 };

async function isGloballyPaused() {
  if (Date.now() - globalState.checkedAt < 5000) return globalState.paused;
  try {
    const reply = await native({ type: "getGlobal" });
    globalState = { paused: Boolean(reply?.blockingPaused), checkedAt: Date.now() };
  } catch {
    globalState.checkedAt = Date.now();
  }
  return globalState.paused;
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.native) {
    native(message.native)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: String(error) }));
    return true; // keep the channel open for the async reply
  }
  if (message?.type === "getGlobal") {
    isGloballyPaused().then((paused) => sendResponse({ blockingPaused: paused }));
    return true;
  }
});
