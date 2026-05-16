import { $ } from './util.js';

let toastTimer;
export function toast(message, type = '') {
  const el = $('#toast');
  el.textContent = message;
  el.className = 'toast ' + type;
  el.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add('hidden'), 2600);
}

export function reportError(err, fallback = 'Something went wrong.') {
  console.error('[axm]', err);
  const msg = (err && err.message) ? err.message : fallback;
  if (msg !== 'cancel') toast(msg, 'error');
}
