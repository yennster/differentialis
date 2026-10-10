(() => {
  "use strict";
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const fine = matchMedia("(pointer: fine)").matches;

  /* ---------------------------------------------------------- Starfield */
  const canvas = document.getElementById("sky");
  const ctx = canvas.getContext("2d", { alpha: true });
  let W = 0, H = 0, DPR = 1, stars = [], shooters = [];
  const tints = ["255,255,255", "255,255,255", "205,185,255", "150,205,250"];

  // pointer + smoothed parallax / glow targets
  let pX = innerWidth / 2, pY = innerHeight / 2;
  let mx = 0, my = 0, plx = 0, ply = 0, gx = pX, gy = pY;

  function resize() {
    DPR = Math.min(devicePixelRatio || 1, 2);
    W = canvas.width = Math.floor(innerWidth * DPR);
    H = canvas.height = Math.floor(innerHeight * DPR);
    canvas.style.width = innerWidth + "px";
    canvas.style.height = innerHeight + "px";
    const count = Math.min(240, Math.round((innerWidth * innerHeight) / 8500));
    stars = Array.from({ length: count }, () => {
      const z = Math.random() * 0.8 + 0.2;
      return {
        x: Math.random() * W, y: Math.random() * H, z,
        r: (z * 1.5 + 0.25) * DPR,
        tw: Math.random() * Math.PI * 2, sp: Math.random() * 0.018 + 0.004,
        tint: tints[(Math.random() * tints.length) | 0],
      };
    });
  }

  let lastSpawn = 0, nextSpawn = 1400;
  function maybeSpawn(t) {
    if (reduce || shooters.length >= 3 || t - lastSpawn < nextSpawn) return;
    lastSpawn = t; nextSpawn = 1800 + Math.random() * 3400;
    const fromLeft = Math.random() > 0.35;
    const angle = Math.random() * 0.22 * Math.PI + 0.1 * Math.PI;
    const speed = (7 + Math.random() * 5) * DPR;
    const dir = fromLeft ? 1 : -1;
    shooters.push({
      x: fromLeft ? Math.random() * W * 0.5 : W * 0.5 + Math.random() * W * 0.5,
      y: Math.random() * H * 0.42,
      vx: Math.cos(angle) * speed * dir, vy: Math.sin(angle) * speed,
      len: (100 + Math.random() * 170) * DPR, life: 1,
    });
  }

  function drawStars() {
    const ox = plx * 16 * DPR, oy = ply * 16 * DPR;
    for (const s of stars) {
      if (!reduce) s.tw += s.sp;
      const a = Math.max(0, 0.45 + Math.sin(s.tw) * 0.4) * s.z;
      ctx.globalAlpha = a;
      ctx.fillStyle = "rgba(" + s.tint + ",1)";
      ctx.beginPath();
      ctx.arc(s.x + ox * s.z, s.y + oy * s.z, s.r, 0, 6.2832);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function drawShooters() {
    for (let i = shooters.length - 1; i >= 0; i--) {
      const sh = shooters[i];
      sh.x += sh.vx; sh.y += sh.vy; sh.life -= 0.011;
      if (sh.life <= 0 || sh.x < -240 || sh.x > W + 240 || sh.y > H + 240) { shooters.splice(i, 1); continue; }
      const m = Math.hypot(sh.vx, sh.vy);
      const tx = sh.x - (sh.vx / m) * sh.len, ty = sh.y - (sh.vy / m) * sh.len;
      const g = ctx.createLinearGradient(sh.x, sh.y, tx, ty);
      g.addColorStop(0, "rgba(255,255,255," + 0.95 * sh.life + ")");
      g.addColorStop(0.3, "rgba(205,185,255," + 0.5 * sh.life + ")");
      g.addColorStop(1, "rgba(205,185,255,0)");
      ctx.strokeStyle = g; ctx.lineWidth = 2 * DPR; ctx.lineCap = "round";
      ctx.beginPath(); ctx.moveTo(sh.x, sh.y); ctx.lineTo(tx, ty); ctx.stroke();
      ctx.beginPath(); ctx.arc(sh.x, sh.y, 1.9 * DPR, 0, 6.2832);
      ctx.fillStyle = "rgba(255,255,255," + sh.life + ")"; ctx.fill();
    }
  }

  const glow = document.getElementById("glow");
  const parallaxEls = [...document.querySelectorAll(".parallax")];

  function frame(t) {
    ctx.clearRect(0, 0, W, H);
    // smooth follow
    plx += (mx - plx) * 0.06; ply += (my - ply) * 0.06;
    drawStars();
    maybeSpawn(t);
    drawShooters();
    if (fine) {
      gx += (pX - gx) * 0.14; gy += (pY - gy) * 0.14;
      glow.style.transform = "translate(" + gx + "px," + gy + "px)";
      for (const el of parallaxEls) {
        const d = parseFloat(el.dataset.depth || "1");
        el.style.transform = "translate3d(" + (-plx * d * 14) + "px," + (-ply * d * 14) + "px,0)";
      }
    }
    requestAnimationFrame(frame);
  }

  resize();
  addEventListener("resize", resize, { passive: true });
  if (reduce) { drawStars(); } else { requestAnimationFrame(frame); }

  /* ----------------------------------------------------------- Pointer */
  if (fine) {
    addEventListener("pointermove", (e) => {
      pX = e.clientX; pY = e.clientY;
      mx = (e.clientX / innerWidth - 0.5) * 2;
      my = (e.clientY / innerHeight - 0.5) * 2;
    }, { passive: true });
    addEventListener("pointermove", () => { glow.style.opacity = "1"; }, { once: true });
  }

  /* ------------------------------------------------------ Tilt + glare */
  if (fine && !reduce) {
    for (const el of document.querySelectorAll("[data-tilt]")) {
      el.addEventListener("pointerenter", () => { el.style.transition = "transform .1s ease-out"; });
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        const px = (e.clientX - r.left) / r.width, py = (e.clientY - r.top) / r.height;
        el.style.transform =
          "perspective(900px) rotateX(" + (0.5 - py) * 7 + "deg) rotateY(" + (px - 0.5) * 9 + "deg)";
        el.style.setProperty("--gx", px * 100 + "%");
        el.style.setProperty("--gy", py * 100 + "%");
      });
      el.addEventListener("pointerleave", () => {
        el.style.transition = "transform .6s cubic-bezier(.22,1,.36,1)";
        el.style.transform = "";
      });
    }

    /* ------------------------------------------------- Magnetic buttons */
    for (const m of document.querySelectorAll(".magnetic")) {
      m.addEventListener("pointermove", (e) => {
        const r = m.getBoundingClientRect();
        m.style.transform =
          "translate(" + (e.clientX - r.left - r.width / 2) * 0.25 + "px," +
          (e.clientY - r.top - r.height / 2) * 0.4 + "px)";
      });
      m.addEventListener("pointerleave", () => { m.style.transform = ""; });
    }
  }

  /* --------------------------------------------------------- Reveal */
  const io = new IntersectionObserver((entries) => {
    for (const en of entries) if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
  }, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
  document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));

  /* --------------------------------------------------------- Nav state */
  const nav = document.getElementById("nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 24);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ----------------------------------------- Latest release (download) */
  fetch("https://api.github.com/repos/yennster/differentialis/releases", {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject()))
    .then((releases) => {
      if (!Array.isArray(releases) || releases.length === 0) return;
      const rel = releases.find((r) => (r.assets || []).some((a) => a.name && a.name.endsWith(".dmg"))) || releases[0];
      const tag = rel.tag_name || "v0.2.2";
      const dmg = (rel.assets || []).find((a) => a.name && a.name.endsWith(".dmg"));
      const url = dmg ? dmg.browser_download_url : rel.html_url;
      if (url) document.querySelectorAll("[data-dl]").forEach((a) => (a.href = url));
      document.querySelectorAll("[data-version]").forEach((s) => (s.textContent = tag));
    })
    .catch(() => {});
})();
