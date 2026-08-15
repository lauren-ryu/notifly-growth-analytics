/**
 * Notifly Measurement — Framer lead-match tracking
 *
 * Purpose
 * -------
 * Capture a lightweight matching log when a valid Framer form is submitted,
 * so lead exports can later be connected to GA4 session identifiers.
 *
 * Public-repository notes
 * -----------------------
 * - Replace placeholders only in a private deployment.
 * - Do not publish the real Apps Script Web App URL.
 * - No form-field values or direct PII are collected here.
 * - Query strings and URL fragments are intentionally excluded from page_location.
 *
 * Matching flow
 * -------------
 * Framer form submit
 *   → read GA4 client/session identifiers
 *   → POST a small matching record
 *   → Apps Script log
 *   → privacy_safe_lead_matching.py
 */

(() => {
  "use strict";

  const GA4_MEASUREMENT_ID = "G-XXXXXXXXXX";
  const LOG_ENDPOINT = "YOUR_APPS_SCRIPT_WEB_APP_URL";

  const FORM_ROUTES = {
    "/": {
      form_name: "form1",
      form_page: "lp1",
    },
    "/welcome": {
      form_name: "form2",
      form_page: "lp2",
    },
  };

  function getCookie(name) {
    const prefix = `${name}=`;
    const cookies = document.cookie ? document.cookie.split(";") : [];

    for (const rawCookie of cookies) {
      const cookie = rawCookie.trim();

      if (cookie.startsWith(prefix)) {
        return decodeURIComponent(cookie.slice(prefix.length));
      }
    }

    return "";
  }

  function getGaClientId() {
    const gaCookie = getCookie("_ga");

    if (!gaCookie) {
      return "";
    }

    const parts = gaCookie.split(".");

    if (parts.length < 4) {
      return "";
    }

    return parts.slice(-2).join(".");
  }

  function getGaSessionCookie() {
    const propertySuffix = GA4_MEASUREMENT_ID.replace(/^G-/, "");

    if (!propertySuffix || propertySuffix === "XXXXXXXXXX") {
      return "";
    }

    return getCookie(`_ga_${propertySuffix}`);
  }

  function getGaSessionId() {
    const sessionCookie = getGaSessionCookie();

    if (!sessionCookie) {
      return "";
    }

    const gs2Match = sessionCookie.match(/(?:^|[.$])s(\d+)(?:[$.]|$)/);

    if (gs2Match) {
      return gs2Match[1];
    }

    const parts = sessionCookie.split(".");

    if (parts.length >= 3 && /^GS\d+$/.test(parts[0])) {
      return parts[2] || "";
    }

    return "";
  }

  function normalizePath(pathname) {
    if (!pathname) {
      return "/";
    }

    if (pathname !== "/" && pathname.endsWith("/")) {
      return pathname.slice(0, -1);
    }

    return pathname;
  }

  function getFormContext() {
    const path = normalizePath(window.location.pathname);
    return FORM_ROUTES[path] || null;
  }

  function createLeadId() {
    if (
      typeof crypto !== "undefined" &&
      typeof crypto.randomUUID === "function"
    ) {
      return crypto.randomUUID();
    }

    return `lead_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  }

  function buildSafePageLocation() {
    return `${window.location.origin}${normalizePath(window.location.pathname)}`;
  }

  function buildMatchingPayload(formContext) {
    return {
      captured_at: new Date().toISOString(),
      form_name: formContext.form_name,
      form_page: formContext.form_page,
      ga_client_id: getGaClientId(),
      ga_session_id: getGaSessionId(),
      lead_id: createLeadId(),
      page_location: buildSafePageLocation(),
    };
  }

  function sendMatchingLog(payload) {
    if (
      !LOG_ENDPOINT ||
      LOG_ENDPOINT === "YOUR_APPS_SCRIPT_WEB_APP_URL"
    ) {
      console.info(
        "[lead-match] LOG_ENDPOINT is a public placeholder; request not sent."
      );
      return;
    }

    fetch(LOG_ENDPOINT, {
      method: "POST",
      mode: "no-cors",
      keepalive: true,
      headers: {
        "Content-Type": "text/plain;charset=UTF-8",
      },
      body: JSON.stringify(payload),
    }).catch((error) => {
      console.warn("[lead-match] Matching log request failed:", error);
    });
  }

  function handleSubmit(event) {
    const form = event.target;

    if (!(form instanceof HTMLFormElement)) {
      return;
    }

    const formContext = getFormContext();

    if (!formContext) {
      return;
    }

    const payload = buildMatchingPayload(formContext);
    sendMatchingLog(payload);
  }

  document.addEventListener("submit", handleSubmit, true);
})();
