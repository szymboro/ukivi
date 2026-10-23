"use strict";

const $ = (id) => document.getElementById(id);

async function native(message) {
  const reply = await browser.runtime.sendMessage({ native: message });
  if (!reply || reply.error) throw new Error(reply?.error || "No reply from uKivi app");
  return reply;
}

async function main() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  let url;
  try {
    url = new URL(tab.url);
  } catch {
    url = null;
  }

  if (!url || !/^https?:$/.test(url.protocol)) {
    $("host").textContent = "Not a website";
    $("pick").disabled = true;
    return;
  }

  const host = url.hostname.replace(/^www\./, "");
  const storageKey = `site:${host}`;
  $("host").textContent = host;

  const loadSite = async () => (await browser.storage.local.get(storageKey))[storageKey] || { hidden: [], paused: false };

  // Hidden elements
  const renderHidden = (site) => {
    $("hidden-row").hidden = site.hidden.length === 0;
    $("hidden-count").textContent = site.hidden.length;
  };
  renderHidden(await loadSite());

  $("reset").addEventListener("click", async () => {
    const site = await loadSite();
    site.hidden = [];
    await browser.storage.local.set({ [storageKey]: site });
    renderHidden(site);
  });

  $("pick").addEventListener("click", async () => {
    await browser.tabs.sendMessage(tab.id, { type: "startPicker" });
    window.close();
  });

  // Pause / resume (shared allowlist lives in the app)
  const toggle = $("enabled");
  const renderPaused = (paused) => {
    toggle.checked = !paused;
    $("pause-status").textContent = paused ? "Paused: nothing is blocked here" : "Ads and trackers are blocked";
  };

  try {
    const { paused, blockingPaused } = await native({ type: "getSite", host });
    renderPaused(paused);
    if (blockingPaused) {
      toggle.checked = false;
      $("pause-status").textContent = "uKivi is switched off in the app";
      $("message").textContent = "Turn blocking back on in the uKivi app.";
    } else {
      toggle.disabled = false;
    }
  } catch (error) {
    $("message").textContent = "Couldn't reach the uKivi app. Open it once, then try again.";
  }

  toggle.addEventListener("change", async () => {
    const paused = !toggle.checked;
    toggle.disabled = true;
    try {
      const reply = await native({ type: "setPaused", host, paused });
      renderPaused(reply.paused);
      const site = await loadSite();
      site.paused = reply.paused;
      await browser.storage.local.set({ [storageKey]: site });

      if (reply.applied) {
        browser.tabs.reload(tab.id);
        window.close();
      } else {
        $("message").textContent = "Saved. Open the uKivi app once to apply it.";
      }
    } catch (error) {
      renderPaused(!paused);
      $("message").textContent = `Couldn't change this: ${error.message}`;
    } finally {
      toggle.disabled = false;
    }
  });
}

main();
