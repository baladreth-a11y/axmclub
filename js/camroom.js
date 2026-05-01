// Cam room. Two coexisting flows:
//   1. Legacy time-limited pass (10 min) — driven by /api/cam/status +
//      /api/cam/redeem-password.
//   2. New cam2cam — peer-to-peer WebRTC kicked off from the Online column
//      and managed by camCall.js. Both sides need cam2cam = true.
// The page swaps between four cam-state panels: locked / live / liveCall /
// incoming. Only one is visible at a time.
import { $ } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { openModal } from './modal.js';
import {
  startCall, openCallerOnAccept, acceptCall, declineCall, endCall,
  toggleMicMuted, toggleVideoMuted, isMicMuted, isVideoMuted, onCallStateChange
} from './camCall.js';

const POLL_STATUS_MS = 30_000;
const POLL_ONLINE_MS = 5_000;
const POLL_INBOX_MS  = 2_000;

let countdownTimer = null;
let statusTimer    = null;
let onlineTimer    = null;
let inboxTimer     = null;
let callTimerInt   = null;

let lastInboxStamp = 0;
// Calls already handled by the UI (so the same accepted callId doesn't
// re-trigger openCallerOnAccept on every poll).
const seenCalls = new Map();   // id -> last status we acted on

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

function formatCountdown(ms) {
  if (ms <= 0) return '00:00';
  const total = Math.floor(ms / 1000);
  const mm = String(Math.floor(total / 60)).padStart(2, '0');
  const ss = String(total % 60).padStart(2, '0');
  return `${mm}:${ss}`;
}

// --- State swap helpers ----------------------------------------------------
function showState(name) {
  const map = {
    locked:    '#camLocked',
    live:      '#camLive',
    liveCall:  '#camLiveCall',
    incoming:  '#camIncoming'
  };
  for (const key of Object.keys(map)) {
    const el = document.querySelector(map[key]);
    if (!el) continue;
    el.classList.toggle('hidden', key !== name);
  }
}

// --- Legacy pass system ---------------------------------------------------
function renderPassState(activeExpiresAt) {
  const callState = (store.get().cam && store.get().cam.call) || {};
  if (callState.status && callState.status !== 'idle' && callState.status !== 'ended') {
    // The cam2cam call view owns the stage while a call is up.
    return;
  }
  const now = Date.now();
  const remaining = Math.max(0, (activeExpiresAt || 0) - now);
  const passActive = remaining > 0;
  showState(passActive ? 'live' : 'locked');
  if (passActive) {
    const cd = $('#camCountdown');
    if (cd) cd.textContent = formatCountdown(remaining);
  }
}

function startCountdown(expiresAt) {
  clearInterval(countdownTimer);
  countdownTimer = setInterval(() => {
    const remaining = Math.max(0, expiresAt - Date.now());
    const cd = $('#camCountdown');
    if (cd) cd.textContent = formatCountdown(remaining);
    if (remaining <= 0) {
      clearInterval(countdownTimer);
      countdownTimer = null;
      renderPassState(0);
      refreshStatus();
    }
  }, 1000);
}

async function refreshStatus() {
  const user = store.get().user;
  if (!user) {
    showState('locked');
    const hint = $('#camHint');
    if (hint) hint.textContent = 'Sign in to the club to claim a pass or send a cam2cam request.';
    return;
  }
  const hint = $('#camHint');
  if (hint) hint.textContent = 'Send a cam2cam request to anyone online, or unlock a 10-minute pass to watch a model stream.';
  try {
    const s = await api.camStatus();
    store.set(state => ({ ...state, cam: { ...state.cam, active: s.active, expiresAt: s.expiresAt, remainingMs: s.remainingMs } }));
    renderPassState(s.expiresAt);
    if (s.active) startCountdown(s.expiresAt);
  } catch {
    renderPassState(0);
  }
}

async function onPasswordSubmit(e) {
  e.preventDefault();
  const input = $('#camPasswordInput');
  if (!input) return;
  const password = (input.value || '').trim();
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
      cam: { ...state.cam, active: true, expiresAt: res.camPassExpires, remainingMs: res.remainingMs }
    }));
    input.value = '';
    renderPassState(res.camPassExpires);
    startCountdown(res.camPassExpires);
    toast(`Pass unlocked — ${res.note || 'enjoy the stream'}.`, 'success');
  } catch (err) {
    if (err.status === 401) { openModal('login'); toast('Sign in first.'); return; }
    toast(err.message, 'error');
  }
}

// --- Cam2cam: online list ------------------------------------------------
function renderOnline(users) {
  const ul = $('#camOnlineList');
  const hint = $('#camOnlineHint');
  if (!ul) return;
  const me = store.get().user;
  if (!me) {
    ul.innerHTML = '';
    if (hint) hint.textContent = 'Sign in and turn on cam2cam to see who\u2019s available.';
    return;
  }
  if (!users || !users.length) {
    ul.innerHTML = '<li class="cam-online-empty muted">No one else is online right now.</li>';
    if (hint) hint.textContent = me.cam2cam ? 'Cam2cam is on. Waiting for peers.' : 'Turn on cam2cam to call peers when they appear.';
    return;
  }
  if (hint) {
    hint.textContent = me.cam2cam
      ? 'Click \u201CRequest cam2cam\u201D next to anyone who has it on.'
      : 'Turn on cam2cam below to start sending requests.';
  }
  ul.innerHTML = users.map(u => {
    const canCall = !!(me.cam2cam && u.cam2cam);
    return `
      <li class="cam-online-item ${u.isModel ? 'is-model' : ''}" data-peer="${escapeHtml(u.email)}">
        <span class="cam-online-dot" data-online="true"></span>
        <div class="cam-online-main">
          <strong>${escapeHtml(u.name || u.email)}</strong>
          <small class="muted">${u.isModel ? 'Model' : 'Supporter'}${u.cam2cam ? ' \u00b7 \u{1F3A5} ready' : ''}</small>
        </div>
        <button type="button" class="btn cam-online-call ${canCall ? 'btn-primary' : 'btn-outline'}"
                data-peer="${escapeHtml(u.email)}" data-name="${escapeHtml(u.name || u.email)}"
                ${canCall ? '' : 'disabled aria-disabled="true"'}>
          \u{1F3A5} Cam2cam
        </button>
      </li>`;
  }).join('');
}

async function fetchOnline() {
  const me = store.get().user;
  if (!me) { renderOnline([]); return; }
  try {
    const { users } = await api.online();
    store.set(state => ({ ...state, online: users || [] }));
    renderOnline(users || []);
  } catch (err) {
    if (err.status === 401) renderOnline([]);
  }
}

function startOnlineTimer() {
  if (onlineTimer) clearInterval(onlineTimer);
  onlineTimer = setInterval(fetchOnline, POLL_ONLINE_MS);
}
function stopOnlineTimer() { if (onlineTimer) { clearInterval(onlineTimer); onlineTimer = null; } }

// --- Cam2cam: incoming inbox + caller-side accept handler ----------------
async function fetchInbox() {
  if (!store.get().user) return;
  try {
    const { calls, now } = await api.camInbox(lastInboxStamp);
    if (typeof now === 'number') lastInboxStamp = Math.max(lastInboxStamp, now);
    for (const c of calls || []) {
      lastInboxStamp = Math.max(lastInboxStamp, c.touchedAt | 0);
      const lastSeen = seenCalls.get(c.id);
      if (lastSeen === c.status) continue;   // already reacted to this state
      seenCalls.set(c.id, c.status);

      if (c.role === 'callee' && c.status === 'pending') {
        showIncoming(c);
      } else if (c.role === 'caller' && c.status === 'accepted') {
        // Peer accepted our request — start the offer flow.
        try {
          await openCallerOnAccept(c.id, c.to, c.toName);
          showState('liveCall');
          updateCallStatusLabel('Connecting\u2026');
        } catch (err) {
          toast(err.message || 'Could not start cam2cam.', 'error');
        }
      } else if (c.status === 'declined' && c.role === 'caller') {
        toast(`${c.toName || c.to} declined the cam2cam request.`);
        renderPassState(store.get().cam.expiresAt);
      } else if (c.status === 'ended') {
        // Peer hung up before we did.
        const callState = store.get().cam.call;
        if (callState && callState.id === c.id && callState.status !== 'idle') {
          await endCall();
          toast('Call ended.');
        }
        // Drop incoming banner if it was for this call.
        const incomingId = $('#camIncoming')?.dataset.callId;
        if (incomingId === c.id) hideIncoming();
      }
    }
  } catch (err) {
    if (err.status === 401) {
      stopInboxTimer();
    }
  }
}

function startInboxTimer() {
  if (inboxTimer) clearInterval(inboxTimer);
  inboxTimer = setInterval(fetchInbox, POLL_INBOX_MS);
}
function stopInboxTimer() { if (inboxTimer) { clearInterval(inboxTimer); inboxTimer = null; } }

// --- Cam2cam: incoming UI ------------------------------------------------
function showIncoming(call) {
  const banner = $('#camIncoming');
  const from = $('#camIncomingFrom');
  if (!banner) return;
  banner.dataset.callId = call.id;
  banner.dataset.peer   = call.from;
  banner.dataset.name   = call.fromName;
  if (from) from.textContent = `${call.fromName || call.from} wants to start a cam2cam call.`;
  showState('incoming');
}
function hideIncoming() {
  const banner = $('#camIncoming');
  if (!banner) return;
  banner.dataset.callId = '';
  banner.dataset.peer   = '';
  banner.dataset.name   = '';
  // Fall back to the appropriate idle state.
  renderPassState(store.get().cam.expiresAt);
}

async function onIncomingAccept() {
  const banner = $('#camIncoming');
  if (!banner) return;
  const id = banner.dataset.callId;
  const peer = banner.dataset.peer;
  const name = banner.dataset.name;
  if (!id) return;
  hideIncoming();
  showState('liveCall');
  updateCallStatusLabel('Connecting\u2026');
  try {
    await acceptCall(id, peer, name);
  } catch (err) {
    toast(err.message || 'Could not accept call.', 'error');
    showState('locked');
  }
}

async function onIncomingDecline() {
  const banner = $('#camIncoming');
  if (!banner) return;
  const id = banner.dataset.callId;
  hideIncoming();
  if (id) {
    try { await declineCall(id); } catch {}
  }
}

// --- Call status / timer + control buttons -------------------------------
function updateCallStatusLabel(text) {
  const el = $('#camCallStatus');
  if (el) el.textContent = text;
}

function startCallTimer(startedAt) {
  if (callTimerInt) clearInterval(callTimerInt);
  const t0 = startedAt || Date.now();
  const tick = () => {
    const el = $('#camCallTimer');
    if (!el) return;
    el.textContent = formatCountdown(Date.now() - t0 + 1000);
  };
  tick();
  callTimerInt = setInterval(tick, 1000);
}
function stopCallTimer() {
  if (callTimerInt) { clearInterval(callTimerInt); callTimerInt = null; }
  const el = $('#camCallTimer');
  if (el) el.textContent = '00:00';
}

function applyCallState(call) {
  if (!call) return;
  const status = call.status || 'idle';
  if (status === 'live' || status === 'connecting') {
    showState('liveCall');
    updateCallStatusLabel(status === 'live' ? 'Live' : 'Connecting\u2026');
    if (status === 'live') startCallTimer(call.startedAt);
  } else if (status === 'requesting') {
    updateCallStatusLabel('Waiting for accept\u2026');
  } else if (status === 'ended' || status === 'failed' || status === 'idle') {
    stopCallTimer();
    if (status !== 'idle' && call.error) toast(call.error, status === 'failed' ? 'error' : 'info');
    // Switch back to the pass-driven view.
    renderPassState(store.get().cam.expiresAt);
  }
}

// --- Cam2cam: my opt-in toggle + request action -------------------------
async function onC2cToggle(e) {
  if (!store.get().user) {
    e.preventDefault();
    openModal('login');
    return;
  }
  const enabled = !!e.target.checked;
  try {
    const res = await api.setCam2cam(enabled);
    if (res && res.user) store.set({ user: res.user });
    updateC2cStatus();
    toast(enabled ? 'Cam2cam is on. You can send and receive requests.' : 'Cam2cam turned off.');
    fetchOnline();
  } catch (err) {
    e.target.checked = !enabled;
    toast(err.message || 'Could not update cam2cam.', 'error');
  }
}

function updateC2cStatus() {
  const me = store.get().user;
  const cb = $('#camC2cToggle');
  const lbl = $('#camC2cStatus');
  const on = !!(me && me.cam2cam);
  if (cb) cb.checked = on;
  if (cb) cb.disabled = !me;
  if (lbl) lbl.textContent = me ? (on ? 'On' : 'Off') : 'Sign in';
}

async function onCallButton(e) {
  const btn = e.target.closest('.cam-online-call');
  if (!btn || btn.disabled) return;
  const peer = btn.dataset.peer;
  const name = btn.dataset.name || peer;
  if (!peer) return;
  const me = store.get().user;
  if (!me) { openModal('login'); return; }
  if (!me.cam2cam) {
    toast('Turn on cam2cam first.', 'info');
    return;
  }
  try {
    await startCall(peer, name);
    updateCallStatusLabel(`Waiting for ${name} to accept\u2026`);
    showState('liveCall');
    toast(`Cam2cam request sent to ${name}.`);
  } catch (err) {
    if (err.status === 403 && err.data && err.data.reason === 'cam2cam-off') {
      toast(`${name} hasn\u2019t enabled cam2cam yet.`, 'info');
      return;
    }
    toast(err.message || 'Could not send request.', 'error');
  }
}

function onMicToggle() {
  const muted = toggleMicMuted();
  const btn = $('#camToggleMic');
  if (btn) btn.textContent = muted ? '\u{1F507} Unmute mic' : '\u{1F399}\uFE0F Mute mic';
}
function onVideoToggle() {
  const muted = toggleVideoMuted();
  const btn = $('#camToggleVideo');
  if (btn) btn.textContent = muted ? '\u{1F4F7} Show camera' : '\u{1F4F9} Mute camera';
}
async function onEnd() {
  await endCall();
  toast('Call ended.');
}

// --- Wiring ---------------------------------------------------------------
export function initCamroom() {
  // Legacy pass form.
  const pwForm = $('#camPasswordForm');
  if (pwForm) pwForm.addEventListener('submit', onPasswordSubmit);

  // Cam2cam toggle + online list interactions.
  const cb = $('#camC2cToggle');
  if (cb) cb.addEventListener('change', onC2cToggle);
  const refresh = $('#camOnlineRefresh');
  if (refresh) refresh.addEventListener('click', fetchOnline);
  const onlineList = $('#camOnlineList');
  if (onlineList) onlineList.addEventListener('click', onCallButton);

  // Incoming call buttons.
  const accept = $('#camIncomingAccept');
  if (accept) accept.addEventListener('click', onIncomingAccept);
  const decline = $('#camIncomingDecline');
  if (decline) decline.addEventListener('click', onIncomingDecline);

  // Live call controls.
  const micBtn = $('#camToggleMic');
  if (micBtn) micBtn.addEventListener('click', onMicToggle);
  const vidBtn = $('#camToggleVideo');
  if (vidBtn) vidBtn.addEventListener('click', onVideoToggle);
  const endBtn = $('#camEndCall');
  if (endBtn) endBtn.addEventListener('click', onEnd);

  // Open chat helper button (placeholder; communicator panel handles UI).
  const openChat = $('#camOpenChat');
  if (openChat) {
    openChat.addEventListener('click', () => {
      const fab = document.getElementById('commFab');
      if (fab) fab.click();
    });
  }

  // Keep cam room in sync with user changes (login, redeem, cam2cam toggle).
  store.subscribe(state => {
    const exp = state.user ? state.user.camPassExpires : 0;
    if (!state.cam || !state.cam.call || state.cam.call.status === 'idle') {
      renderPassState(exp || 0);
    }
    updateC2cStatus();
    if (state.user) {
      if (!onlineTimer) { fetchOnline(); startOnlineTimer(); }
      if (!inboxTimer)  { fetchInbox();  startInboxTimer(); }
    } else {
      stopOnlineTimer();
      stopInboxTimer();
      renderOnline([]);
    }
    if (exp && exp > Date.now()) startCountdown(exp);
  });

  // Watch the cam.call slice for status transitions.
  onCallStateChange(applyCallState);

  // Initial load.
  refreshStatus();
  updateC2cStatus();
  if (store.get().user) {
    fetchOnline(); startOnlineTimer();
    fetchInbox();  startInboxTimer();
  }
  if (statusTimer) clearInterval(statusTimer);
  statusTimer = setInterval(refreshStatus, POLL_STATUS_MS);

  document.addEventListener('axm:redeem-complete', refreshStatus);
}
