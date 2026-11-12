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
    const el = $('status'), hint = $('hint'), btn = $('setupBtn'), help = $('helpLink');
    if (!s) return;
    hint.hidden = btn.hidden = help.hidden = true;
    el.style.color = '';
    const err = s.error;

    if (s.setup === 'started') {
      el.textContent = 'Setup is running. Allow the admin prompt, then press Enter in the setup window.';
      el.style.color = '#ffd36b';
    } else if (err && err.code === 'no-permission') {
      el.textContent = err.message + ' Click below and allow the admin prompt.';
      el.style.color = '#ffd36b';
      btn.hidden = false;
      btn.disabled = false;
      if (err.folder) { hint.hidden = false; hint.textContent = 'Or run install.bat from: ' + err.folder; }
    } else if (err && err.code === 'not-installed') {
      el.textContent = 'Toolbar colouring is not set up yet.';
      el.style.color = '#ffd36b';
      hint.hidden = false;
      hint.textContent = 'Open the toolbar-glow folder you downloaded and double click install.bat, then reload this extension.';
      help.hidden = false;
    } else if (err) {
      el.textContent = 'Toolbar helper: ' + err.message;
      el.style.color = '#ff8a8a';
    } else if (s.connected) {
      el.textContent = 'Toolbar colouring on' + (s.applied ? ' · ' + s.applied : '');
      el.style.color = '#8aff9e';
    } else {
      el.textContent = 'Toolbar helper not connected';
    }
  });
}

$('setupBtn').addEventListener('click', () => {
  $('setupBtn').disabled = true;
  chrome.runtime.sendMessage({ type: 'run-setup' });
});
status();
setInterval(status, 1500);
