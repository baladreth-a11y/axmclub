import { $, escapeHtml } from './util.js';
import { api } from './api.js';
import { store } from './store.js';

function tierBadgeClass(tier) {
  const t = (tier || '').toLowerCase();
  if (t === 'platinum') return 'badge badge-accent';
  if (t === 'gold')     return 'badge badge-gold';
  return 'badge badge-muted';
}

function podiumHtml(row, rank) {
  if (!row) return '';
  const initial = (row.name[0] || '?').toUpperCase();
  const glowClass = row.nameGlow ? 'name-glow' : '';
  const badgeHtml = row.badge ? `<span class="badge-supporter ${row.badge}">${escapeHtml(row.badge)}</span>` : '';
  
  let rankIcon = '👑';
  let levelColor = 'var(--gold)';
  if (rank === 2) { rankIcon = '🥈'; levelColor = '#a8b2c1'; }
  if (rank === 3) { rankIcon = '🥉'; levelColor = '#c48858'; }

  return `
    <div class="podium-step podium-${rank}">
      <div class="podium-avatar-wrapper" style="border-color: ${levelColor};">
        <span class="podium-rank-badge">${rankIcon}</span>
        <span class="podium-avatar">${escapeHtml(initial)}</span>
      </div>
      <div class="podium-info">
        <strong class="podium-name ${glowClass}">${escapeHtml(row.name)}</strong>${badgeHtml}
        <span class="${tierBadgeClass(row.tier)}">${escapeHtml(row.tier || 'Silver')}</span>
        <div class="podium-pts"><b>${(row.points || 0).toLocaleString()}</b> <small>pts</small></div>
      </div>
      <div class="podium-base" style="background: linear-gradient(180deg, ${levelColor}22, rgba(0,0,0,0.1)); border-top: 3px solid ${levelColor};">
        <span class="podium-base-number">${rank}</span>
      </div>
    </div>`;
}

function rowHtml(row, i, meName) {
  const rank = i + 1;
  const isMe = meName && row.name === meName;
  const initial = (row.name[0] || '?').toUpperCase();
  const glowClass = row.nameGlow ? 'name-glow' : '';
  const badgeHtml = row.badge ? `<span class="badge-supporter ${row.badge}">${escapeHtml(row.badge)}</span>` : '';
  return `
    <li class="rank-${rank} ${isMe ? 'is-me' : ''}">
      <span class="lb-rank">${rank}</span>
      <span class="lb-name">
        <span class="lb-avatar">${escapeHtml(initial)}</span>
        <span class="lb-name-inner ${glowClass}">${escapeHtml(row.name)}</span>${badgeHtml}
      </span>
      <span class="lb-tier">
        <span class="${tierBadgeClass(row.tier)}">${escapeHtml(row.tier || 'Silver')}</span>
      </span>
      <span class="lb-points">${(row.points || 0).toLocaleString()}</span>
    </li>`;
}

function render(state) {
  const list = $('#leaderboardList');
  const podium = $('#leaderboardPodium');
  const rows = state.leaderboard || [];

  if (rows.length === 0) {
    if (podium) podium.innerHTML = '';
    if (list) list.innerHTML = '<li class="lb-empty">No members yet. Be the first to spin.</li>';
    return;
  }

  const meName = state.user ? state.user.name : null;

  // Render top 3 in 3D podium layout
  if (podium) {
    const top1 = rows[0] || null;
    const top2 = rows[1] || null;
    const top3 = rows[2] || null;

    podium.innerHTML = `
      ${podiumHtml(top2, 2)}
      ${podiumHtml(top1, 1)}
      ${podiumHtml(top3, 3)}
    `;
  }

  // Render the remaining ranks (from index 3 onwards) in the scrolling list
  const listRows = rows.slice(3);
  if (list) {
    if (listRows.length === 0) {
      list.innerHTML = '<li class="lb-empty">No other ranks to show.</li>';
    } else {
      list.innerHTML = listRows.map((r, i) => rowHtml(r, i + 3, meName)).join('');
    }
  }
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
  const list = $('#leaderboardList');
  if (!list) return;
  render(store.get());
  store.subscribe(render);
  // Refresh when a spin completes (fired by wheel.js).
  document.dispatchEvent(new CustomEvent('axm:spin-complete'));
  document.addEventListener('axm:spin-complete', refreshLeaderboard);
  // Passive polling in case someone else spun.
  setInterval(refreshLeaderboard, 60_000);
}
