import { $ } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { openModal } from './modal.js';

let countdownTimer = null;
let pollTimer = null;

function formatCountdown(ms) {
  if (ms <= 0) return '00:00';
  const total = Math.floor(ms / 1000);
  const mm = String(Math.floor(total / 60)).padStart(2, '0');
  const ss = String(total % 60).padStart(2, '0');
  return `${mm}:${ss}`;
}

function renderState(activeExpiresAt) {
  const now = Date.now();
  const remaining = Math.max(0, (activeExpiresAt || 0) - now);
  const active = remaining > 0;
  $('#camLocked').classList.toggle('hidden', active);
  $('#camLive').classList.toggle('hidden', !active);
  if (active) {
    $('#camCountdown').textContent = formatCountdown(remaining);
  }
}

function startCountdown(expiresAt) {
  clearInterval(countdownTimer);
  countdownTimer = setInterval(() => {
    const remaining = Math.max(0, expiresAt - Date.now());
    if (remaining <= 0) {
      clearInterval(countdownTimer);
      renderState(0);
      refreshStatus(); // confirm with server
      return;
    }
    $('#camCountdown').textContent = formatCountdown(remaining);
  }, 1000);
}

async function refreshStatus() {
  const user = store.get().user;
  if (!user) {
    // Anonymous view: show locked with a sign-in hint.
    $('#camLocked').classList.remove('hidden');
    $('#camLive').classList.add('hidden');
    $('#camHint').textContent = 'Sign in to the club to claim or enter a pass.';
    return;
  }
  $('#camHint').textContent = 'Enter a model-issued code, redeem 1,500 pts in the catalog, or earn enough points from daily tasks.';

  try {
    const s = await api.camStatus();
    store.set(state => ({ ...state, cam: s }));
    renderState(s.expiresAt);
    if (s.active) startCountdown(s.expiresAt);
  } catch {
    renderState(0);
  }
}

async function onPasswordSubmit(e) {
  e.preventDefault();
  const input = $('#camPasswordInput');
  const password = input.value.trim();
  if (!password) return;
  if (!store.get().user) {
    openModal('login');
    toast('Please sign in to redeem a code.');
    return;
  }
  try {
    const res = await api.camRedeemPassword(password);
    store.set(state => ({
      ...state,
      user: res.user,
      cam: { active: true, expiresAt: res.camPassExpires, remainingMs: res.remainingMs }
    }));
    input.value = '';
    renderState(res.camPassExpires);
    startCountdown(res.camPassExpires);
    toast(`Pass unlocked — ${res.note || 'enjoy the stream'}.`, 'success');
  } catch (err) {
    if (err.status === 401) { openModal('login'); toast('Sign in first.'); return; }
    toast(err.message, 'error');
  }
}

export function initCamroom() {
  // Keep cam room in sync with user changes (login, spin, redeem).
  store.subscribe(state => {
    const exp = state.user ? state.user.camPassExpires : 0;
    renderState(exp || 0);
    if (exp && exp > Date.now()) startCountdown(exp);
  });

  $('#camPasswordForm').addEventListener('submit', onPasswordSubmit);

  // Initial load + passive polling every 30s in case the server expires the pass.
  refreshStatus();
  clearInterval(pollTimer);
  pollTimer = setInterval(refreshStatus, 30_000);

  document.addEventListener('axm:redeem-complete', refreshStatus);
}
