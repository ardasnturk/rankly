/* Rankly website — shared behaviour (vanilla JS, no dependencies) */
(function () {
  "use strict";

  var doc = document.documentElement;
  doc.classList.add("js");
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ------------------------------------------------------------------
   * i18n — English lives in the HTML; Turkish comes from assets/i18n.js
   * ------------------------------------------------------------------ */
  var TR = window.RANKLY_TR || {};
  var STORE_KEY = "rankly-lang";
  var enText = new Map();   // element -> original innerHTML
  var enAttr = new Map();   // element -> {attr: original}
  var lang = "en";

  function storedLang() {
    try { return window.localStorage.getItem(STORE_KEY); } catch (e) { return null; }
  }
  function saveLang(l) {
    try { window.localStorage.setItem(STORE_KEY, l); } catch (e) { /* storage unavailable */ }
  }
  function detectLang() {
    var s = storedLang();
    if (s === "en" || s === "tr") return s;
    var nav = (navigator.languages && navigator.languages[0]) || navigator.language || "en";
    return /^tr\b/i.test(nav) ? "tr" : "en";
  }

  function t(key, fallback) {
    if (lang === "tr" && Object.prototype.hasOwnProperty.call(TR, key)) return TR[key];
    return fallback;
  }

  function parseAttrSpec(spec) {
    return spec.split(";").map(function (p) {
      var i = p.indexOf(":");
      return i > 0 ? [p.slice(0, i).trim(), p.slice(i + 1).trim()] : null;
    }).filter(Boolean);
  }

  function applyLang(l) {
    lang = l;
    doc.setAttribute("lang", l);
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      if (!enText.has(el)) enText.set(el, el.innerHTML);
      var key = el.getAttribute("data-i18n");
      var html = l === "tr" && TR[key] !== undefined ? TR[key] : enText.get(el);
      if (el.tagName === "TITLE") document.title = html.replace(/&amp;/g, "&");
      else if (el.innerHTML !== html) el.innerHTML = html;
    });
    document.querySelectorAll("[data-i18n-attr]").forEach(function (el) {
      var pairs = parseAttrSpec(el.getAttribute("data-i18n-attr"));
      if (!enAttr.has(el)) {
        var orig = {};
        pairs.forEach(function (p) { orig[p[0]] = el.getAttribute(p[0]) || ""; });
        enAttr.set(el, orig);
      }
      pairs.forEach(function (p) {
        var v = l === "tr" && TR[p[1]] !== undefined ? TR[p[1]] : enAttr.get(el)[p[0]];
        el.setAttribute(p[0], v);
      });
    });
    document.querySelectorAll(".lang-toggle button[data-lang]").forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-lang") === l ? "true" : "false");
    });
    document.dispatchEvent(new CustomEvent("rankly:lang", { detail: l }));
  }

  document.querySelectorAll(".lang-toggle button[data-lang]").forEach(function (b) {
    b.addEventListener("click", function () {
      var l = b.getAttribute("data-lang");
      saveLang(l);
      applyLang(l);
    });
  });
  applyLang(detectLang());
  window.RanklyI18n = { t: function (k, f) { return t(k, f); }, lang: function () { return lang; } };

  /* ------------------------------------------------------------------
   * Mobile nav
   * ------------------------------------------------------------------ */
  var menuBtn = document.querySelector(".menu-btn");
  var navLinks = document.getElementById("nav-links");
  if (menuBtn && navLinks) {
    menuBtn.addEventListener("click", function () {
      var open = navLinks.classList.toggle("open");
      menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
    });
    navLinks.addEventListener("click", function (e) {
      if (e.target.closest("a")) {
        navLinks.classList.remove("open");
        menuBtn.setAttribute("aria-expanded", "false");
      }
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && navLinks.classList.contains("open")) {
        navLinks.classList.remove("open");
        menuBtn.setAttribute("aria-expanded", "false");
        menuBtn.focus();
      }
    });
  }

  /* ------------------------------------------------------------------
   * Footer year
   * ------------------------------------------------------------------ */
  document.querySelectorAll("[data-year]").forEach(function (el) { el.textContent = String(new Date().getFullYear()); });

  /* ------------------------------------------------------------------
   * Scroll reveal
   * ------------------------------------------------------------------ */
  var revealEls = document.querySelectorAll(".reveal");
  var onReveal = [];   // callbacks keyed by element
  function whenVisible(el, fn) { onReveal.push({ el: el, fn: fn }); if (io) io.observe(el); }
  var io = null;
  if ("IntersectionObserver" in window && !reduceMotion) {
    io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        en.target.classList.add("in");
        onReveal.forEach(function (r) { if (r.el === en.target && !r.done) { r.done = true; r.fn(); } });
        io.unobserve(en.target);
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add("in"); });
    whenVisible = function (el, fn) { fn(); };
  }

  /* ------------------------------------------------------------------
   * Card glow + subtle tilt
   * ------------------------------------------------------------------ */
  var finePointer = window.matchMedia && window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  if (finePointer) {
    document.querySelectorAll(".card[data-tilt], .card").forEach(function (card) {
      card.addEventListener("pointermove", function (e) {
        var r = card.getBoundingClientRect();
        var x = e.clientX - r.left, y = e.clientY - r.top;
        card.style.setProperty("--mx", x + "px");
        card.style.setProperty("--my", y + "px");
        if (!reduceMotion && card.hasAttribute("data-tilt")) {
          var rx = ((y / r.height) - 0.5) * -5;
          var ry = ((x / r.width) - 0.5) * 6;
          card.style.transform = "perspective(900px) rotateX(" + rx.toFixed(2) + "deg) rotateY(" + ry.toFixed(2) + "deg) translateY(-2px)";
        }
      });
      card.addEventListener("pointerleave", function () { card.style.transform = ""; });
    });
  }

  /* ------------------------------------------------------------------
   * Count-up numbers
   * ------------------------------------------------------------------ */
  document.querySelectorAll("[data-count]").forEach(function (el) {
    var target = parseInt(el.getAttribute("data-count"), 10);
    if (reduceMotion || !target) { el.textContent = String(target); return; }
    el.textContent = "0";
    whenVisible(el.closest(".reveal") || el, function () {
      var start = null, dur = 1400;
      function step(ts) {
        if (!start) start = ts;
        var p = Math.min(1, (ts - start) / dur);
        var eased = 1 - Math.pow(1 - p, 3);
        el.textContent = String(Math.round(target * eased));
        if (p < 1) requestAnimationFrame(step);
      }
      requestAnimationFrame(step);
    });
  });

  /* ------------------------------------------------------------------
   * Animated rising line chart
   * ------------------------------------------------------------------ */
  document.querySelectorAll(".chart-svg").forEach(function (svg) {
    var line = svg.querySelector(".line");
    if (!line || !line.getTotalLength) { svg.classList.add("drawn"); return; }
    if (reduceMotion) { svg.classList.add("drawn"); return; }
    var len = Math.ceil(line.getTotalLength());
    line.style.strokeDasharray = len;
    line.style.strokeDashoffset = len;
    whenVisible(svg.closest(".reveal") || svg, function () {
      line.getBoundingClientRect();
      line.style.transition = "stroke-dashoffset 2.2s cubic-bezier(.45,.05,.2,1) .2s";
      line.style.strokeDashoffset = "0";
      svg.classList.add("drawn");
    });
  });

  /* ------------------------------------------------------------------
   * Screenshots: once a real PNG loads, size the box to it and drop the
   * placeholder frame (the PNG already shows the macOS window).
   * Missing files are handled by the inline onerror in the HTML.
   * ------------------------------------------------------------------ */
  document.querySelectorAll(".shot-media > img").forEach(function (img) {
    function ready() {
      if (!img.naturalWidth) return;
      var media = img.parentNode;
      media.classList.remove("missing");
      media.style.aspectRatio = img.naturalWidth + " / " + img.naturalHeight;
      var win = media.closest(".window");
      if (win) win.classList.add("loaded");
    }
    if (img.complete) ready(); else img.addEventListener("load", ready);
  });

  /* ------------------------------------------------------------------
   * Copy button (keyword field demo)
   * ------------------------------------------------------------------ */
  document.querySelectorAll("[data-copy-target]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var src = document.getElementById(btn.getAttribute("data-copy-target"));
      if (!src) return;
      var text = src.textContent.trim();
      var done = function () {
        var label = btn.querySelector("[data-i18n]") || btn;
        var prev = label.innerHTML;
        label.innerHTML = t("ui.copied", "Copied!");
        setTimeout(function () { label.innerHTML = prev; }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, done);
      } else { done(); }
    });
  });

  /* ------------------------------------------------------------------
   * Guide / privacy: active table-of-contents link
   * ------------------------------------------------------------------ */
  var tocLinks = document.querySelectorAll(".toc a[href^='#']");
  if (tocLinks.length && "IntersectionObserver" in window) {
    var map = {};
    tocLinks.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a; });
    var tocIO = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          tocLinks.forEach(function (a) { a.classList.remove("active"); });
          var a = map[en.target.id];
          if (a) a.classList.add("active");
        }
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    Object.keys(map).forEach(function (id) { var s = document.getElementById(id); if (s) tocIO.observe(s); });
  }

  /* ------------------------------------------------------------------
   * Live keyword table demo
   * ------------------------------------------------------------------ */
  var body = document.getElementById("kw-body");
  if (body) {
    var rows = [
      { term: "habit tracker", rank: 4, pop: 78, diff: 82 },
      { term: "daily routine", rank: 9, pop: 54, diff: 47 },
      { term: "streak app", rank: 14, pop: 31, diff: 28 },
      { term: "goal planner", rank: 22, pop: 46, diff: 58 },
      { term: "morning routine", rank: 37, pop: 39, diff: 41 },
      { term: "self care", rank: 88, pop: 62, diff: 74 },
      { term: "to do list", rank: null, pop: 81, diff: 93 }
    ];
    rows.forEach(function (r, i) {
      r.id = i;
      r.change = [2, 0, 5, -1, 3, -6, 0][i];
      r.hist = [];
      var base = r.rank || 260;
      for (var k = 0; k < 10; k++) {
        var v = r.rank ? Math.max(1, Math.round(base + (10 - k) * (i % 2 ? 0.9 : 1.6) + Math.sin(k * 1.3 + i) * 3)) : 260;
        r.hist.push(v);
      }
      r.hist[9] = base;
    });

    var svgNS = "http://www.w3.org/2000/svg";
    function sparkPath(hist) {
      var w = 96, h = 28, pad = 3;
      var min = Math.min.apply(null, hist), max = Math.max.apply(null, hist);
      if (max - min < 4) { max += 2; min -= 2; }
      return hist.map(function (v, i) {
        var x = (i / (hist.length - 1)) * w;
        var y = pad + ((v - min) / (max - min)) * (h - pad * 2); // lower rank = higher on chart
        return (i ? "L" : "M") + x.toFixed(1) + " " + y.toFixed(1);
      }).join(" ");
    }

    function badgeHTML(c, ranked) {
      if (!ranked || !c) return '<span class="badge flat" aria-label="no change">—</span>';
      var up = c > 0;
      return '<span class="badge ' + (up ? "up" : "down") + '">' + (up ? "▲ " : "▼ ") + Math.abs(c) + "</span>";
    }

    function rankText(r) { return r.rank ? "#" + r.rank : ">250"; }

    function buildRow(r) {
      var el = document.createElement("div");
      el.className = "kw-row";
      el.setAttribute("role", "row");
      el.dataset.id = r.id;
      el.innerHTML =
        '<div class="kw-term" role="cell"></div>' +
        '<div class="kw-rank" role="cell"></div>' +
        '<div class="kw-change" role="cell"></div>' +
        '<div class="meter pop" role="cell"><div class="track"><div class="fill"></div></div><span></span></div>' +
        '<div class="meter diff kw-col-diff" role="cell"><div class="track"><div class="fill"></div></div><span></span></div>' +
        '<div class="kw-col-trend" role="cell"><svg class="spark" viewBox="0 0 96 28" aria-hidden="true"><path/></svg></div>';
      el.querySelector(".kw-term").textContent = r.term;
      r.el = el;
      paint(r);
      return el;
    }

    function paint(r) {
      var el = r.el;
      var rk = el.querySelector(".kw-rank");
      rk.textContent = rankText(r);
      rk.classList.toggle("out", !r.rank);
      el.querySelector(".kw-change").innerHTML = badgeHTML(r.change, !!r.rank);
      var pop = el.querySelector(".meter.pop");
      pop.querySelector(".fill").style.width = r.pop + "%";
      pop.querySelector("span").textContent = r.pop;
      var diff = el.querySelector(".meter.diff");
      diff.querySelector(".fill").style.width = r.diff + "%";
      diff.querySelector(".fill").style.backgroundPosition = "0 0";
      diff.querySelector("span").textContent = r.diff;
      var path = el.querySelector(".spark path");
      path.setAttribute("d", sparkPath(r.hist));
      var trendUp = r.hist[r.hist.length - 1] <= r.hist[0];
      path.style.stroke = r.rank ? (trendUp ? "var(--up)" : "var(--down)") : "var(--muted)";
    }

    rows.forEach(function (r) { body.appendChild(buildRow(r)); });

    function sortRows() {
      var first = new Map();
      rows.forEach(function (r) { first.set(r, r.el.getBoundingClientRect().top); });
      rows.sort(function (a, b) { return (a.rank || 999) - (b.rank || 999); });
      rows.forEach(function (r) { body.appendChild(r.el); });
      rows.forEach(function (r) {
        var dy = first.get(r) - r.el.getBoundingClientRect().top;
        if (!dy) return;
        r.el.style.transition = "none";
        r.el.style.transform = "translateY(" + dy + "px)";
        r.el.style.zIndex = "2";
        requestAnimationFrame(function () {
          requestAnimationFrame(function () {
            r.el.style.transition = "transform .7s cubic-bezier(.2,.8,.2,1), background .6s";
            r.el.style.transform = "";
            setTimeout(function () { r.el.style.zIndex = ""; }, 700);
          });
        });
      });
    }

    function tick() {
      var ranked = rows.filter(function (r) { return r.rank; });
      var n = 1 + Math.floor(Math.random() * 2);
      for (var i = 0; i < n; i++) {
        var r = ranked[Math.floor(Math.random() * ranked.length)];
        var delta = Math.floor(Math.random() * 5) + 1;
        var dir = Math.random() < 0.6 ? -1 : 1; // more ups than downs
        var next = Math.max(1, Math.min(240, r.rank + dir * delta));
        if (next === r.rank) continue;
        r.change = r.rank - next;
        r.rank = next;
        r.hist.push(next); r.hist.shift();
        if (Math.random() < 0.3) r.pop = Math.max(5, Math.min(100, r.pop + (Math.random() < 0.5 ? -2 : 2)));
        paint(r);
        var row = r.el;
        row.classList.remove("flash-up", "flash-down");
        row.classList.add(r.change > 0 ? "flash-up" : "flash-down");
        (function (rowEl) { setTimeout(function () { rowEl.classList.remove("flash-up", "flash-down"); }, 900); })(row);
      }
      sortRows();
    }

    if (!reduceMotion) {
      var timer = null;
      var running = false;
      var inView = !("IntersectionObserver" in window);
      var start = function () { if (!running && inView && !document.hidden) { running = true; timer = setInterval(tick, 2300); } };
      var stop = function () { running = false; clearInterval(timer); };
      if ("IntersectionObserver" in window) {
        new IntersectionObserver(function (e) { inView = e[0].isIntersecting; inView ? start() : stop(); }, { threshold: 0.2 }).observe(body);
      } else { start(); }
      document.addEventListener("visibilitychange", function () { document.hidden ? stop() : start(); });
    }
  }
})();
