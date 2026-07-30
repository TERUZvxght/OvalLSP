/* OvalLSP official site — no dependencies. */
(function () {
  "use strict";

  /* ---- Theme ------------------------------------------------------- */

  var STORE_KEY = "ovallsp-theme";
  var root = document.documentElement;

  function applyTheme(theme) {
    if (theme === "light") root.setAttribute("data-theme", "light");
    else root.removeAttribute("data-theme");
  }

  function currentTheme() {
    return root.getAttribute("data-theme") === "light" ? "light" : "dark";
  }

  document.addEventListener("click", function (e) {
    var toggle = e.target.closest("[data-theme-toggle]");
    if (!toggle) return;
    var next = currentTheme() === "light" ? "dark" : "light";
    applyTheme(next);
    try { localStorage.setItem(STORE_KEY, next); } catch (err) { /* private mode */ }
    toggle.setAttribute("aria-label", next === "light" ? "Switch to dark theme" : "Switch to light theme");
  });

  /* ---- Mobile navigation ------------------------------------------- */

  var navToggle = document.querySelector("[data-nav-toggle]");
  var nav = document.getElementById("site-nav");

  if (navToggle && nav) {
    navToggle.addEventListener("click", function () {
      var open = nav.classList.toggle("is-open");
      navToggle.setAttribute("aria-expanded", String(open));
    });
    nav.addEventListener("click", function (e) {
      if (e.target.tagName === "A") {
        nav.classList.remove("is-open");
        navToggle.setAttribute("aria-expanded", "false");
      }
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("is-open")) {
        nav.classList.remove("is-open");
        navToggle.setAttribute("aria-expanded", "false");
        navToggle.focus();
      }
    });
  }

  /* ---- Language switch: remember the choice ------------------------ */

  document.addEventListener("click", function (e) {
    var link = e.target.closest("[data-lang-switch]");
    if (!link) return;
    try { localStorage.setItem("ovallsp-lang", link.getAttribute("data-lang-switch")); } catch (err) { /* ignore */ }
  });

  /* ---- Copy buttons on code blocks --------------------------------- */

  document.querySelectorAll(".codeblock").forEach(function (block) {
    var pre = block.querySelector("pre");
    if (!pre) return;
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "copy-btn";
    var idle = block.getAttribute("data-copy-label") || "Copy";
    var done = block.getAttribute("data-copied-label") || "Copied";
    btn.textContent = idle;
    btn.addEventListener("click", function () {
      var text = pre.innerText.replace(/^\s*[$#]\s?/gm, "");
      var reset = function () { setTimeout(function () { btn.textContent = idle; }, 1600); };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { btn.textContent = done; reset(); });
      } else {
        var ta = document.createElement("textarea");
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); btn.textContent = done; reset(); } catch (err) { /* ignore */ }
        document.body.removeChild(ta);
      }
    });
    block.appendChild(btn);
  });

  /* ---- Reveal on scroll -------------------------------------------- */

  var revealables = document.querySelectorAll(".reveal");
  if (revealables.length) {
    if (!("IntersectionObserver" in window)) {
      revealables.forEach(function (el) { el.classList.add("is-in"); });
    } else {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        });
      }, { rootMargin: "0px 0px -8% 0px", threshold: 0.06 });
      revealables.forEach(function (el, i) {
        el.style.transitionDelay = Math.min(i % 4, 3) * 60 + "ms";
        io.observe(el);
      });
    }
  }

  /* ---- Capability matrix filtering --------------------------------- */

  var matrix = document.querySelector("[data-matrix]");
  if (matrix) {
    var rows = Array.prototype.slice.call(matrix.querySelectorAll("tbody tr"));
    var countEl = document.querySelector("[data-matrix-count]");
    var countTemplate = countEl ? countEl.getAttribute("data-template") || "{n} / {total}" : null;
    var searchInput = document.querySelector("[data-matrix-search]");
    var state = { status: "all", query: "" };

    function rowMatches(row) {
      if (state.status !== "all" && row.getAttribute("data-status") !== state.status) return false;
      if (state.query && row.getAttribute("data-text").indexOf(state.query) === -1) return false;
      return true;
    }

    function apply() {
      var shown = 0;
      rows.forEach(function (row) {
        var ok = rowMatches(row);
        row.hidden = !ok;
        if (ok) shown++;
      });
      if (countEl) {
        countEl.textContent = countTemplate
          .replace("{n}", String(shown))
          .replace("{total}", String(rows.length));
      }
    }

    rows.forEach(function (row) {
      row.setAttribute("data-text", row.textContent.toLowerCase());
    });

    document.querySelectorAll("[data-status-filter]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        state.status = btn.getAttribute("data-status-filter");
        document.querySelectorAll("[data-status-filter]").forEach(function (other) {
          other.setAttribute("aria-pressed", String(other === btn));
        });
        apply();
      });
    });

    if (searchInput) {
      searchInput.addEventListener("input", function () {
        state.query = searchInput.value.trim().toLowerCase();
        apply();
      });
    }

    apply();
  }

  /* ---- Current year ------------------------------------------------ */

  document.querySelectorAll("[data-year]").forEach(function (el) {
    el.textContent = String(new Date().getFullYear());
  });
})();
