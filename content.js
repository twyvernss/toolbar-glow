(() => {
  if (window.__toolbarGlow) return;
  window.__toolbarGlow = true;

  const DEFAULTS = { enabled: true, video: true, sites: true, intensity: 0.65, height: 120 };
  const COLS = 7;
  const hasExt = typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.id;
  let cfg = { ...DEFAULTS };

  const bar = document.createElement('div');
  bar.id = '__toolbar-glow__';
  const fade = 'linear-gradient(to bottom, #000 0%, rgba(0,0,0,.6) 30%, rgba(0,0,0,.18) 65%, transparent 100%)';
  Object.assign(bar.style, {
    position: 'fixed', top: '0', left: '0', right: '0', height: '0px',
    pointerEvents: 'none', zIndex: '2147483647', opacity: '0',
    transition: 'opacity 400ms ease, height 300ms ease',
    webkitMaskImage: fade, maskImage: fade,
  });
  (document.documentElement || document).appendChild(bar);

  function parseColor(str) {
    const m = /rgba?\(([^)]+)\)/.exec(str || '');
    if (!m) return null;
    const p = m[1].split(/[\s,/]+/).filter(Boolean).map(Number);
    return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
  }

  function cssToRgb(str) {
    const prev = bar.style.color;
    bar.style.color = '';
    bar.style.color = str;
    const c = bar.style.color ? parseColor(getComputedStyle(bar).color) : null;
    bar.style.color = prev;
    return c ? c.slice(0, 3) : null;
  }

  function vivid([r, g, b]) {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    let h = 0, s = 0, l = (max + min) / 2;
    if (max !== min) {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
      h /= 6;
    }
    s = Math.min(1, s * 1.35);
    l = Math.min(0.68, Math.max(0.1, l * 1.1));
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    const f = t => {
      if (t < 0) t += 1; if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    };
    return s === 0 ? [l * 255, l * 255, l * 255] : [f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255];
  }

  const SW = COLS * 4, SH = 16;
  const cv = document.createElement('canvas');
  cv.width = SW; cv.height = SH;
  const cx = cv.getContext('2d', { willReadFrequently: true });
  const tainted = new WeakSet();

  function mainVideo() {
    let best = null, bestArea = 0;
    for (const v of document.querySelectorAll('video')) {
      const r = v.getBoundingClientRect();
      const a = r.width * r.height;
      if (a > bestArea) { bestArea = a; best = v; }
    }
    return bestArea > innerWidth * innerHeight * 0.12 ? best : null;
  }

  function sampleVideo(v) {
    if (!v || tainted.has(v) || v.readyState < 2 || !v.videoWidth) return null;
    let d;
    try {
      cx.drawImage(v, 0, 0, SW, SH);
      d = cx.getImageData(0, 0, SW, SH).data;
    } catch {
      tainted.add(v);
      return null;
    }
    const out = [];
    for (let c = 0; c < COLS; c++) {
      let r = 0, g = 0, b = 0, w = 0;
      for (let y = 0; y < SH; y++) {
        const wy = y < 6 ? 3 : 1;
        for (let x = c * 4; x < c * 4 + 4; x++) {
          const i = (y * SW + x) * 4;
          if (d[i] + d[i + 1] + d[i + 2] < 30) continue;
          r += d[i] * wy; g += d[i + 1] * wy; b += d[i + 2] * wy; w += wy;
        }
      }
      out.push(w ? vivid([r / w, g / w, b / w]) : [10, 10, 12]);
    }
    return out;
  }

  function themeColor() {
    const metas = [...document.querySelectorAll('meta[name="theme-color"]')];
    const m = metas.find(x => !x.media || matchMedia(x.media).matches);
    return m ? cssToRgb(m.content) : null;
  }

  function bgAt(x, y) {
    let el = document.elementFromPoint(x, y);
    while (el && el !== document.documentElement) {
      const c = parseColor(getComputedStyle(el).backgroundColor);
      if (c && c[3] > 0.5) return c.slice(0, 3);
      el = el.parentElement;
    }
    const html = parseColor(getComputedStyle(document.documentElement).backgroundColor);
    if (html && html[3] > 0.5) return html.slice(0, 3);
    return themeColor() || (matchMedia('(prefers-color-scheme: dark)').matches ? [32, 33, 36] : [255, 255, 255]);
  }

  let topColors = null, topUrl = '';
  function pageColors() {
    if (topColors && topUrl === location.href && scrollY >= 60) return topColors;
    const out = [];
    for (let i = 0; i < COLS; i++) out.push(bgAt(((i + 0.5) / COLS) * innerWidth, 3));
    topColors = out;
    topUrl = location.href;
    return topColors;
  }

  let target = null, cur = null, video = null, mode = 'none';
  let lastVideoCheck = -1e9, lastSample = -1e9, lastPage = -1e9, lastSent = -1e9, sentKey = '';

  function paint() {
    const stops = cur.map((c, i) =>
      `rgb(${c[0] | 0},${c[1] | 0},${c[2] | 0}) ${((i / (COLS - 1)) * 100).toFixed(1)}%`).join(',');
    bar.style.background = `linear-gradient(to right, ${stops})`;
  }

  function report(t, rgb) {
    if (!hasExt) return;
    const key = rgb ? rgb.map(v => v >> 3).join(',') : 'off';
    if (key === sentKey) return;
    if (t - lastSent < (mode === 'video' ? 140 : 60)) return;
    lastSent = t;
    sentKey = key;
    try { chrome.runtime.sendMessage({ type: 'glow-color', rgb }).catch(() => {}); }
    catch {  }
  }

  function tick(t) {
    requestAnimationFrame(tick);

    if (!cfg.enabled || document.fullscreenElement) {
      bar.style.opacity = '0';
      return;
    }

    if (t - lastVideoCheck > 700) {
      video = cfg.video ? mainVideo() : null;
      lastVideoCheck = t;
    }

    let newMode = 'none';
    if (video && t - lastSample > 70) {
      lastSample = t;
      const s = sampleVideo(video);
      if (s) { target = s; newMode = 'video'; }
      else if (cfg.sites) newMode = 'page';
    } else if (video && mode === 'video') {
      newMode = 'video';
    } else if (cfg.sites) {
      newMode = 'page';
    }
    if (newMode === 'page' && (mode !== 'page' || t - lastPage > 800)) {
      lastPage = t;
      target = pageColors();
    }
    if (newMode !== mode) { mode = newMode; sentKey = ''; }

    if (mode === 'none' || !target) {
      bar.style.opacity = '0';
      report(t, null);
      return;
    }

    const first = !cur;
    if (first) cur = target.map(c => c.slice());
    const k = mode === 'video' ? 0.2 : 0.25;
    let moved = 0;
    for (let i = 0; i < COLS; i++) {
      for (let j = 0; j < 3; j++) {
        const d = target[i][j] - cur[i][j];
        cur[i][j] += d * k;
        moved += Math.abs(d);
      }
    }
    if (first || moved > 1) paint();

    const op = String(cfg.intensity);
    if (bar.style.opacity !== op) bar.style.opacity = op;
    const h = cfg.height + 'px';
    if (bar.style.height !== h) bar.style.height = h;
    const blend = mode === 'video' ? 'screen' : 'normal';
    if (bar.style.mixBlendMode !== blend) bar.style.mixBlendMode = blend;

    const avg = [0, 1, 2].map(j => Math.round(target.reduce((s, c) => s + c[j], 0) / target.length));
    report(t, avg);
  }

  const resend = () => { sentKey = ''; lastSent = -1e9; };
  addEventListener('pageshow', resend);
  addEventListener('focus', resend);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) resend(); });

  if (hasExt && chrome.storage) {
    chrome.storage.local.get(DEFAULTS, v => { cfg = { ...DEFAULTS, ...v }; });
    chrome.storage.onChanged.addListener(ch => {
      for (const k in ch) if (k in DEFAULTS) cfg[k] = ch[k].newValue;
      lastVideoCheck = lastPage = -1e9;
      resend();
    });
    chrome.runtime.onMessage.addListener((m, _sender, reply) => {
      if (m && m.type === 'glow-request') { resend(); reply({ ok: true }); }
    });
  }

  requestAnimationFrame(tick);
})();
