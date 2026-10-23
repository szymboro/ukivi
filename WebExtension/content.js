// Runs on every page. Applies the user's own "hide this element" rules and
// provides the tap-to-hide element picker started from the popup.

(() => {
  "use strict";

  const host = location.hostname.replace(/^www\./, "");
  const storageKey = `site:${host}`;
  let styleEl = null;
  let globallyPaused = false; // main switch in the uKivi app

  // ------------------------------------------------------------ saved rules

  async function loadSite() {
    const stored = await browser.storage.local.get(storageKey);
    return stored[storageKey] || { hidden: [], paused: false };
  }

  async function saveSite(site) {
    await browser.storage.local.set({ [storageKey]: site });
  }

  function applyHidden(site) {
    const css = globallyPaused || site.paused || !site.hidden.length
      ? ""
      : `${site.hidden.join(",\n")} { display: none !important; }`;
    // Leave the page completely untouched unless there's something to hide.
    if (!css) {
      styleEl?.remove();
      return;
    }
    if (!styleEl) {
      styleEl = document.createElement("style");
      styleEl.dataset.ukivi = "";
    }
    styleEl.textContent = css;
    if (!styleEl.isConnected) {
      const insert = () => (document.head || document.documentElement).appendChild(styleEl);
      // Wait for <head> so frameworks that rebuild the page don't trip over an early node.
      if (document.head) insert();
      else document.addEventListener("DOMContentLoaded", insert, { once: true });
    }
  }

  loadSite().then(applyHidden);

  // If uKivi is switched off in the app, don't apply the user's hidden elements either.
  browser.runtime
    .sendMessage({ type: "getGlobal" })
    .then(async (reply) => {
      if (reply?.blockingPaused) {
        globallyPaused = true;
        applyHidden(await loadSite());
      }
    })
    .catch(() => {});

  browser.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes[storageKey]) {
      applyHidden(changes[storageKey].newValue || { hidden: [], paused: false });
    }
  });

  // ------------------------------------------------------------ selector generation

  const looksGenerated = (name) => /\d{3,}|^[a-z]{1,2}\d|[A-Z0-9]{6,}|__|--/.test(name);

  function describe(el) {
    if (el.id && !looksGenerated(el.id)) return `#${CSS.escape(el.id)}`;
    let part = el.localName;
    const classes = [...el.classList].filter((c) => !looksGenerated(c)).slice(0, 3);
    if (classes.length) part += classes.map((c) => `.${CSS.escape(c)}`).join("");
    return part;
  }

  // Shortest selector (walking up the tree) that matches only this element.
  function selectorFor(el) {
    const parts = [];
    for (let node = el; node && node !== document.documentElement; node = node.parentElement) {
      let part = describe(node);
      const parent = node.parentElement;
      if (parent) {
        const sameKind = [...parent.children].filter((c) => c.matches(part));
        if (sameKind.length > 1) {
          const index = [...parent.children].filter((c) => c.localName === node.localName).indexOf(node) + 1;
          part += `:nth-of-type(${index})`;
        }
      }
      parts.unshift(part);
      const selector = parts.join(" > ");
      try {
        if (document.querySelectorAll(selector).length === 1) return selector;
      } catch {
        // CSS.escape output is always valid, but be safe.
      }
      if (part.startsWith("#")) return selector;
    }
    return parts.join(" > ");
  }

  // ------------------------------------------------------------ picker

  let picker = null;

  function startPicker() {
    if (picker) return;

    const overlay = document.createElement("div");
    overlay.style.cssText =
      "position:fixed;pointer-events:none;z-index:2147483646;border:2px solid #ff4d55;" +
      "background:rgba(255,77,85,.18);border-radius:4px;transition:all .12s;display:none";

    const bar = document.createElement("div");
    const shadow = bar.attachShadow({ mode: "closed" });
    shadow.innerHTML = `
      <style>
        :host { all: initial; }
        .bar { position: fixed; left: 12px; right: 12px; bottom: max(12px, env(safe-area-inset-bottom));
               z-index: 2147483647; display: flex; gap: 8px; padding: 10px; border-radius: 16px;
               background: rgba(23,23,26,.95); border: 1px solid rgba(255,255,255,.08); color: #fff; font: 15px -apple-system, system-ui, sans-serif;
               box-shadow: 0 8px 30px rgba(0,0,0,.35); align-items: center; }
        .hint { flex: 1; font-size: 13px; opacity: .8; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        button { font: inherit; border: 0; border-radius: 10px; padding: 9px 12px; color: #fff; background: #3a3a3c; }
        button.hide { background: linear-gradient(135deg,#ff4d55,#c2212b); font-weight: 600; }
        button:disabled { opacity: .4; }
      </style>
      <div class="bar">
        <span class="hint">Tap what you want to hide</span>
        <button class="bigger" disabled>Bigger</button>
        <button class="hide" disabled>Hide</button>
        <button class="cancel">Cancel</button>
      </div>`;
    const hint = shadow.querySelector(".hint");
    const biggerBtn = shadow.querySelector(".bigger");
    const hideBtn = shadow.querySelector(".hide");

    let target = null;

    const select = (el) => {
      target = el;
      const r = el.getBoundingClientRect();
      Object.assign(overlay.style, {
        display: "block",
        top: `${r.top}px`,
        left: `${r.left}px`,
        width: `${r.width}px`,
        height: `${r.height}px`,
      });
      hint.textContent = selectorFor(el);
      biggerBtn.disabled = !el.parentElement || el.parentElement === document.body;
      hideBtn.disabled = false;
    };

    // Swallow taps on the page so links and buttons don't fire while picking.
    const onTap = (event) => {
      if (event.composedPath().includes(bar)) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.type === "click") {
        const el = document.elementFromPoint(event.clientX, event.clientY);
        if (el && el !== document.documentElement && el !== document.body) select(el);
      }
    };
    // Not "touchend": cancelling it on iOS stops the click from firing at all.
    const events = ["click", "mousedown", "mouseup", "pointerdown", "pointerup"];
    events.forEach((type) => document.addEventListener(type, onTap, true));

    const reposition = () => target && select(target);
    window.addEventListener("scroll", reposition, true);

    const stop = () => {
      events.forEach((type) => document.removeEventListener(type, onTap, true));
      window.removeEventListener("scroll", reposition, true);
      overlay.remove();
      bar.remove();
      picker = null;
    };

    biggerBtn.addEventListener("click", () => target?.parentElement && select(target.parentElement));
    shadow.querySelector(".cancel").addEventListener("click", stop);
    hideBtn.addEventListener("click", async () => {
      if (!target) return;
      const selector = selectorFor(target);
      const site = await loadSite();
      if (!site.hidden.includes(selector)) site.hidden.push(selector);
      await saveSite(site);
      stop();
    });

    document.documentElement.append(overlay, bar);
    picker = { stop };
  }

  // Only the top frame runs the picker (the manifest doesn't inject into iframes).
  browser.runtime.onMessage.addListener((message) => {
    if (message?.type === "startPicker") startPicker();
  });
})();
