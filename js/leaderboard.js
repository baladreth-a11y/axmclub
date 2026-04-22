import { $, escapeHtml } from './util.js';
import { api } from './api.js';
import { store } from './store.js';

function tierBadgeClass(tier) {
  const t = (tier || '').toLowerCase();
  if (t === 'platinum') return 'badge badge-accent';
  if (t === 'gold')     return 'badge badge-gold';
  return 'badge badge-muted';
}

function rowHtml(row, i, meName) {
  const rank = i + 1;
  const isMe = meName && row.name === meName;
  const initial = (row.name[0] || '?').toUpperCase();
  return `
    <li class="rank-${rank} ${isMe ? 'is-me' : ''}">
      <span class="lb-rank">${rank}</span>
      <span class="lb-name">
        <span class="lb-avatar">${escapeHtml(initial)}</span>
        <span class="lb-name-inner">${escapeHtml(row.name)}</span>
      </span>
      <span class="lb-tier">
        <span class="${tierBadgeClass(row.tier)}">${escapeHtml(row.tier || 'Silver')}</span>
      </span>
      <span class="lb-points">${(row.points || 0).toLocaleString()}</span>
    </li>`;
}

function render(state) {
  const list = $('#leaderboardList');
  const rows = state.leaderboard || [];
  if (rows.length === 0) {
    list.innerHTML = '<li class="lb-empty">No members yet. Be the first to spin.</li>';
    return;
  }
  const meName = state.user ? state.user.name : null;
  list.innerHTML = rows.map((r, i) => rowHtml(r, i, meName)).join('');
}

export async function refreshLeaderboard() {
  try {
    const data = await api.leaderboard();
    store.set({ leaderboard: data.leaderboard || [] });
  } catch {
    $('#leaderboardList').innerHTML =
      '<li class="lb-empty">Could not load leaderboard.</li>';
  }
}

export function initLeaderboard() {
  render(store.get());
  store.subscribe(render);
  // Refresh when a spin completes (fired by wheel.js).
  document.addEventListener('axm:spin-complete', refreshLeaderboard);
  // Passive polling in case someone else spun.
  setInterval(refreshLeaderboard, 60_000);
}
