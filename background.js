const HOST = 'com.toolbarglow.bridge';
const tabColors = new Map();
let settings = { enabled: true, toolbar: true };
let port = null;
let hostFailedAt = 0;
let lastError = null;
let lastApplied = '';
let setupState = '';

chrome.storage.local.get({ enabled: true, toolbar: true }, v => { settings = v; });
chrome.storage.onChanged.addListener(ch => {
  if ('enabled' in ch) settings.enabled = ch.enabled.newValue;
  if ('toolbar' in ch) settings.toolbar = ch.toolbar.newValue;
  if (!settings.enabled || !settings.toolbar) post({ type: 'reset' });
  else pushActiveTab();
});

function getPort() {
  if (port) return port;
  if (Date.now() - hostFailedAt < 10000) return null;
  try {
    port = chrome.runtime.connectNative(HOST);
    port.onMessage.addListener(m => {
      if (m.type === 'error') lastError = m;
      if (m.type === 'setup') setupState = m.state;
      if (m.type === 'applied') { lastError = null; setupState = ''; lastApplied = m.value + (m.mode === 'slow' ? ' (slow mode)' : ''); }
    });
    port.onDisconnect.addListener(() => {
      const msg = (chrome.runtime.lastError && chrome.runtime.lastError.message) || 'Helper disconnected';
      lastError = { code: /not found|forbidden/i.test(msg) ? 'not-installed' : 'other', message: msg };
      port = null;
      hostFailedAt = Date.now();
    });
  } catch (e) {
    lastError = { code: 'other', message: String(e) };
    port = null;
    hostFailedAt = Date.now();
  }
  return port;
}

function post(msg) {
  const p = getPort();
  if (!p) return;
  try { p.postMessage(msg); } catch { port = null; }
}

const toHex = rgb => '#' + rgb.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');

function applyToolbar(rgb) {
  if (!settings.enabled || !settings.toolbar) return;
  post(rgb ? { type: 'color', hex: toHex(rgb) } : { type: 'reset' });
}

function pushTab(tabId) {
  if (tabColors.has(tabId)) { applyToolbar(tabColors.get(tabId)); return; }
  chrome.tabs.sendMessage(tabId, { type: 'glow-request' }).catch(() => applyToolbar(null));
}

function pushActiveTab() {
  chrome.tabs.query({ active: true, lastFocusedWindow: true }, tabs => {
    if (tabs && tabs[0]) pushTab(tabs[0].id);
  });
}

function makeIcon([r, g, b]) {
  const imageData = {};
  for (const s of [16, 32]) {
    const c = new OffscreenCanvas(s, s);
    const x = c.getContext('2d');
    const glow = x.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    glow.addColorStop(0, `rgba(${r},${g},${b},1)`);
    glow.addColorStop(0.55, `rgba(${r},${g},${b},0.9)`);
    glow.addColorStop(1, `rgba(${r},${g},${b},0)`);
    x.fillStyle = glow;
    x.fillRect(0, 0, s, s);
    x.beginPath();
    x.arc(s / 2, s / 2, s * 0.3, 0, Math.PI * 2);
    x.lineWidth = Math.max(1, s / 14);
    x.strokeStyle = 'rgba(255,255,255,0.9)';
    x.stroke();
    imageData[s] = x.getImageData(0, 0, s, s);
  }
  return imageData;
}

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (msg && msg.type === 'glow-color' && sender.tab && sender.tab.id != null) {
    tabColors.set(sender.tab.id, msg.rgb);
    const icon = msg.rgb ? { imageData: makeIcon(msg.rgb) } : { path: { 16: 'icons/16.png', 48: 'icons/48.png' } };
    chrome.action.setIcon({ tabId: sender.tab.id, ...icon }).catch(() => {});
    if (sender.tab.active) applyToolbar(msg.rgb);
  }
  if (msg && msg.type === 'status') {
    getPort();
    reply({ connected: !!port, error: lastError, applied: lastApplied, setup: setupState });
  }
  if (msg && msg.type === 'run-setup') {
    post({ type: 'setup' });
    setTimeout(pushActiveTab, 500);
  }
});

chrome.tabs.onActivated.addListener(({ tabId }) => pushTab(tabId));
chrome.tabs.onRemoved.addListener(tabId => tabColors.delete(tabId));
chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  if (info.status === 'loading') tabColors.delete(tabId);
  if (info.status === 'complete' && tab.active) {
    setTimeout(() => { if (!tabColors.has(tabId)) pushTab(tabId); }, 700);
  }
});
chrome.windows.onFocusChanged.addListener(winId => {
  if (winId !== chrome.windows.WINDOW_ID_NONE) pushActiveTab();
});
