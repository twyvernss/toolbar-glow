const DEFAULTS = { enabled: true, toolbar: true, video: true, sites: true, intensity: 0.65, height: 120 };
const TOGGLES = ['enabled', 'toolbar', 'video', 'sites'];
const $ = id => document.getElementById(id);

function labels() {
  $('intensityV').textContent = Math.round(Number($('intensity').value) * 100) + '%';
  $('heightV').textContent = $('height').value + 'px';
}

chrome.storage.local.get(DEFAULTS, v => {
  for (const id of TOGGLES) $(id).checked = v[id];
  $('intensity').value = v.intensity;
  $('height').value = v.height;
  labels();
});

for (const id of TOGGLES) {
  $(id).addEventListener('change', e => chrome.storage.local.set({ [id]: e.target.checked }).catch(() => {}));
}
const save = (id, value) => chrome.storage.local.set({ [id]: value }).catch(() => {});
const lastSave = {};
const saveTimer = {};
for (const id of ['intensity', 'height']) {
  $(id).addEventListener('input', e => {
    labels();
    const value = Number(e.target.value);
    const now = Date.now();
    clearTimeout(saveTimer[id]);
    if (!lastSave[id] || now - lastSave[id] > 120) { lastSave[id] = now; save(id, value); }
    else saveTimer[id] = setTimeout(() => { lastSave[id] = Date.now(); save(id, value); }, 120);
  });
  $(id).addEventListener('change', e => save(id, Number(e.target.value)));
}

function status() {
  chrome.runtime.sendMessage({ type: 'status' }, s => {
    const el = $('status');
    if (!s) return;
    if (s.error) { el.textContent = 'Toolbar helper: ' + s.error; el.style.color = '#ff8a8a'; }
    else if (s.connected) { el.textContent = 'Toolbar helper connected' + (s.applied ? ' · ' + s.applied : ''); el.style.color = '#8aff9e'; }
    else { el.textContent = 'Toolbar helper not connected'; }
  });
}
status();
setInterval(status, 1500);
