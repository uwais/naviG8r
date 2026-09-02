const CONTACT_ENDPOINT = "https://formsubmit.co/ajax/7eadc0879f93ea0c161305caca38dbf2";
const PORTAL_URL = "https://navig8r-customer.onrender.com/";
const TURNSTILE_SITE_KEY = String(import.meta.env.VITE_TURNSTILE_SITE_KEY || "").trim();
const MIN_INTERACTION_MS = 1600;

function qs(sel, root = document) {
  return root.querySelector(sel);
}

function qsa(sel, root = document) {
  return [...root.querySelectorAll(sel)];
}

function initHeader() {
  const header = qs("[data-header]");
  const toggle = qs("[data-nav-toggle]");
  const mobile = qs("[data-mobile-nav]");
  if (!header) return;

  const onScroll = () => {
    header.classList.toggle("is-scrolled", window.scrollY > 24);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  if (!toggle || !mobile) return;

  const setOpen = (open) => {
    toggle.setAttribute("aria-expanded", String(open));
    mobile.classList.toggle("is-open", open);
    mobile.hidden = !open;
    document.body.classList.toggle("nav-open", open);
  };

  setOpen(false);

  toggle.addEventListener("click", (event) => {
    event.stopPropagation();
    const open = toggle.getAttribute("aria-expanded") === "true";
    setOpen(!open);
  });

  qsa("a", mobile).forEach((a) => {
    a.addEventListener("click", () => setOpen(false));
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setOpen(false);
  });

  document.addEventListener("click", (event) => {
    if (toggle.getAttribute("aria-expanded") !== "true") return;
    if (mobile.contains(event.target) || toggle.contains(event.target)) return;
    setOpen(false);
  });

  window.addEventListener("resize", () => {
    if (window.matchMedia("(min-width: 900px)").matches) setOpen(false);
  });
}

function initProductTabs() {
  const stage = qs("[data-product-stage]");
  if (!stage) return;
  const tabs = qsa("[data-product-tab]", stage);
  const panels = qsa("[data-product-panel]", stage);

  const show = (key) => {
    tabs.forEach((t) => t.setAttribute("aria-selected", String(t.dataset.productTab === key)));
    panels.forEach((p) => {
      const on = p.dataset.productPanel === key;
      p.classList.toggle("is-active", on);
      p.hidden = !on;
    });
  };

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => show(tab.dataset.productTab));
  });
}

function initHowSteps() {
  const root = qs("[data-how]");
  if (!root) return;
  const steps = qsa("[data-how-step]", root);
  const panels = qsa("[data-how-panel]", root);
  let timer;

  const show = (idx) => {
    steps.forEach((s) => {
      const on = Number(s.dataset.howStep) === idx;
      s.classList.toggle("is-active", on);
      s.setAttribute("aria-selected", String(on));
    });
    panels.forEach((p) => {
      const on = Number(p.dataset.howPanel) === idx;
      p.classList.toggle("is-active", on);
      p.hidden = !on;
    });
  };

  const armAutoplay = () => {
    clearInterval(timer);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    timer = setInterval(() => {
      const current = steps.findIndex((s) => s.classList.contains("is-active"));
      show((current + 1) % steps.length);
    }, 5200);
  };

  steps.forEach((step) => {
    step.addEventListener("click", () => {
      show(Number(step.dataset.howStep));
      armAutoplay();
    });
  });

  armAutoplay();
  root.addEventListener("mouseenter", () => clearInterval(timer));
  root.addEventListener("mouseleave", armAutoplay);
}

function initAudience() {
  const section = qs("#audience");
  if (!section) return;
  const tabs = qsa("[data-audience-tab]", section);
  const panels = qsa("[data-audience-panel]", section);

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const key = tab.dataset.audienceTab;
      tabs.forEach((t) => t.classList.toggle("is-active", t === tab));
      panels.forEach((p) => {
        const on = p.dataset.audiencePanel === key;
        p.classList.toggle("is-active", on);
        p.hidden = !on;
      });
    });
  });
}

function initReveal() {
  const items = qsa("[data-reveal]");
  if (!("IntersectionObserver" in window)) {
    items.forEach((el) => el.classList.add("is-visible"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -8% 0px" },
  );
  items.forEach((el) => io.observe(el));
}

let turnstileReady = null;

function loadTurnstile() {
  if (!TURNSTILE_SITE_KEY) return Promise.resolve(null);
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (turnstileReady) return turnstileReady;

  turnstileReady = new Promise((resolve, reject) => {
    const existing = document.querySelector("script[data-turnstile-api]");
    if (existing) {
      existing.addEventListener("load", () => resolve(window.turnstile));
      existing.addEventListener("error", () => reject(new Error("Turnstile failed to load")));
      return;
    }
    const script = document.createElement("script");
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    script.async = true;
    script.dataset.turnstileApi = "true";
    script.onload = () => resolve(window.turnstile);
    script.onerror = () => reject(new Error("Turnstile failed to load"));
    document.head.appendChild(script);
  });

  return turnstileReady;
}

function randomChallenge() {
  const a = 2 + Math.floor(Math.random() * 8);
  const b = 1 + Math.floor(Math.random() * 7);
  return { a, b, sum: a + b };
}

function mountFallbackChallenge(container, idPrefix) {
  const challenge = randomChallenge();
  container.hidden = false;
  container.innerHTML = `
    <label class="human-check">
      <input type="checkbox" data-human-check />
      <span>I’m human (not an automated script)</span>
    </label>
    <div class="human-challenge-row">
      <label for="${idPrefix}-math">What is ${challenge.a} + ${challenge.b}?</label>
      <input id="${idPrefix}-math" type="text" inputmode="numeric" autocomplete="off" data-human-math />
    </div>
    <input type="text" name="website_url" class="hp" tabindex="-1" autocomplete="off" data-human-honey aria-hidden="true" />
  `;
  container.dataset.expected = String(challenge.sum);
  container.dataset.openedAt = String(Date.now());
  return container;
}

function readFallbackChallenge(container) {
  if (!container || container.hidden) {
    return { ok: false, reason: "Complete the human check first." };
  }
  const honey = qs("[data-human-honey]", container);
  if (honey && honey.value.trim()) {
    return { ok: false, reason: "Couldn’t verify this submission." };
  }
  const openedAt = Number(container.dataset.openedAt || 0);
  if (Date.now() - openedAt < MIN_INTERACTION_MS) {
    return { ok: false, reason: "Take a moment to complete the check, then try again." };
  }
  const checked = qs("[data-human-check]", container)?.checked;
  if (!checked) {
    return { ok: false, reason: "Confirm you’re human." };
  }
  const answer = String(qs("[data-human-math]", container)?.value || "").trim();
  if (answer !== container.dataset.expected) {
    return { ok: false, reason: "Check the math answer and try again." };
  }
  return { ok: true, method: "challenge" };
}

function createTurnstileWidget(api, el, { onToken }) {
  el.innerHTML = "";
  return api.render(el, {
    sitekey: TURNSTILE_SITE_KEY,
    theme: "light",
    callback: (token) => onToken(token),
    "expired-callback": () => onToken(""),
    "error-callback": () => onToken(""),
  });
}

async function initContactHuman() {
  const mount = qs("[data-contact-human]");
  const label = qs("[data-contact-human-label]", mount || document);
  const turnstileEl = qs("[data-turnstile-contact]", mount || document);
  if (!TURNSTILE_SITE_KEY || !turnstileEl) {
    return { mode: "formsubmit" };
  }

  try {
    const api = await loadTurnstile();
    if (!api) return { mode: "formsubmit" };
    let token = "";
    const widgetId = createTurnstileWidget(api, turnstileEl, {
      onToken: (value) => {
        token = value;
      },
    });
    if (label) {
      label.textContent = "Human check — required before send";
    }
    return {
      mode: "turnstile",
      getProof: async () => {
        if (!token) {
          return { ok: false, reason: "Complete the human verification checkbox." };
        }
        return { ok: true, method: "turnstile", token };
      },
      reset: () => {
        token = "";
        if (widgetId != null && window.turnstile) window.turnstile.reset(widgetId);
      },
    };
  } catch (err) {
    console.warn(err);
    return { mode: "formsubmit" };
  }
}

function initContactForm(contactHuman) {
  const form = qs("[data-contact-form]");
  if (!form) return;
  const status = qs("[data-form-status]", form);
  const submitBtn = qs("[data-submit]", form);
  const nextField = qs("[data-form-next]", form);
  let openedAt = Date.now();

  if (nextField) {
    const next = new URL(window.location.href);
    next.searchParams.set("sent", "1");
    next.hash = "contact";
    nextField.value = next.toString();
  }

  if (new URLSearchParams(window.location.search).get("sent") === "1") {
    status.textContent = "Message sent. We’ll reply at hello@navig8r.org soon.";
    const clean = new URL(window.location.href);
    clean.searchParams.delete("sent");
    window.history.replaceState({}, "", `${clean.pathname}${clean.search}${clean.hash || "#contact"}`);
  }

  form.addEventListener(
    "focusin",
    () => {
      if (!form.dataset.touched) {
        form.dataset.touched = "1";
        openedAt = Date.now();
      }
    },
    { once: true },
  );

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    status.textContent = "";
    status.classList.remove("is-error");

    if (!form.reportValidity()) {
      status.textContent = "Please complete the required fields.";
      status.classList.add("is-error");
      return;
    }

    const honey = form.querySelector('input[name="_gotcha"]');
    if (honey && honey.value.trim()) {
      status.textContent = "Couldn’t verify this submission.";
      status.classList.add("is-error");
      return;
    }

    if (Date.now() - openedAt < MIN_INTERACTION_MS) {
      status.textContent = "Take a moment to review your message, then send again.";
      status.classList.add("is-error");
      return;
    }

    if (!contactHuman || contactHuman.mode !== "turnstile") {
      submitBtn.disabled = true;
      submitBtn.textContent = "Sending…";
      HTMLFormElement.prototype.submit.call(form);
      return;
    }

    const proof = await contactHuman.getProof();
    if (!proof.ok) {
      status.textContent = proof.reason || "Complete the human check first.";
      status.classList.add("is-error");
      return;
    }

    const data = new FormData(form);
    data.append("_captcha", "false");
    data.append("human_verification", proof.method);
    if (proof.token) data.append("cf-turnstile-response", proof.token);

    submitBtn.disabled = true;
    const prev = submitBtn.textContent;
    submitBtn.textContent = "Sending…";

    try {
      const res = await fetch(CONTACT_ENDPOINT, {
        method: "POST",
        body: data,
        headers: { Accept: "application/json" },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      form.reset();
      openedAt = Date.now();
      delete form.dataset.touched;
      contactHuman.reset?.();
      status.textContent = "Message sent. We’ll reply at hello@navig8r.org soon.";
    } catch (err) {
      console.error(err);
      status.textContent =
        "Couldn’t send just now. Email us directly at hello@navig8r.org.";
      status.classList.add("is-error");
    } finally {
      submitBtn.disabled = false;
      submitBtn.textContent = prev;
    }
  });
}

function initHumanGate() {
  const backdrop = qs("[data-human-gate]");
  if (!backdrop) {
    return {
      verify: async () => ({ ok: false, reason: "Verification UI missing." }),
    };
  }

  const panel = qs(".human-gate-panel", backdrop);
  const turnstileEl = qs("[data-turnstile-gate]", backdrop);
  const fallbackEl = qs("[data-gate-fallback]", backdrop);
  const errorEl = qs("[data-human-gate-error]", backdrop);
  const cancelBtn = qs("[data-human-gate-cancel]", backdrop);
  const confirmBtn = qs("[data-human-gate-confirm]", backdrop);
  let token = "";
  let widgetId = null;
  let usingTurnstile = false;
  let active = null;

  const setError = (msg) => {
    if (!errorEl) return;
    if (!msg) {
      errorEl.hidden = true;
      errorEl.textContent = "";
      return;
    }
    errorEl.hidden = false;
    errorEl.textContent = msg;
  };

  const close = (result) => {
    backdrop.hidden = true;
    setError("");
    if (widgetId != null && window.turnstile) {
      try {
        window.turnstile.remove(widgetId);
      } catch {
        /* ignore */
      }
      widgetId = null;
    }
    token = "";
    const resolve = active;
    active = null;
    if (resolve) resolve(result);
  };

  cancelBtn?.addEventListener("click", () => close({ ok: false, cancelled: true }));

  backdrop.addEventListener("click", (event) => {
    if (event.target === backdrop) close({ ok: false, cancelled: true });
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !backdrop.hidden) {
      close({ ok: false, cancelled: true });
    }
  });

  confirmBtn?.addEventListener("click", () => {
    if (usingTurnstile) {
      if (!token) {
        setError("Complete the human verification first.");
        return;
      }
      close({ ok: true, method: "turnstile", token });
      return;
    }
    const proof = readFallbackChallenge(fallbackEl);
    if (!proof.ok) {
      setError(proof.reason);
      return;
    }
    close(proof);
  });

  return {
    verify: async () => {
      if (active) return { ok: false, cancelled: true };

      return new Promise(async (resolve) => {
        active = resolve;
        setError("");
        backdrop.hidden = false;
        panel?.focus?.();
        token = "";
        usingTurnstile = false;

        if (TURNSTILE_SITE_KEY && turnstileEl) {
          try {
            const api = await loadTurnstile();
            if (api) {
              usingTurnstile = true;
              if (fallbackEl) fallbackEl.hidden = true;
              turnstileEl.hidden = false;
              widgetId = createTurnstileWidget(api, turnstileEl, {
                onToken: (value) => {
                  token = value;
                },
              });
              return;
            }
          } catch (err) {
            console.warn(err);
          }
        }

        if (turnstileEl) turnstileEl.hidden = true;
        mountFallbackChallenge(fallbackEl, "gate");
      });
    },
  };
}

function initPortalGate(humanGate) {
  qsa("[data-portal-gate]").forEach((link) => {
    link.addEventListener("click", async (event) => {
      event.preventDefault();
      const href = link.getAttribute("href") || PORTAL_URL;
      const result = await humanGate.verify();
      if (!result.ok) return;
      window.open(href, "_blank", "noopener,noreferrer");
    });
  });
}

function initYear() {
  const el = qs("[data-year]");
  if (el) el.textContent = String(new Date().getFullYear());
}

async function boot() {
  initHeader();
  initProductTabs();
  initHowSteps();
  initAudience();
  initReveal();
  initYear();

  const contactHuman = await initContactHuman();
  const humanGate = initHumanGate();
  initContactForm(contactHuman);
  initPortalGate(humanGate);
}

boot();
