import { $, escapeHtml, tierFor, nextTierInfo, formatDate, formatRelative } from './util.js';
import { store } from './store.js';
import { api } from './api.js';
import { registerView } from './modal.js';

function renderHeader() {
  const { user } = store.get();
  if (!user) return;

  $('#profileAvatar').textContent = (user.name[0] || 'U').toUpperCase();
  $('#profileName').textContent = user.name;
  $('#profileEmail').textContent = user.email;
  $('#profileTier').textContent = (user.tier || tierFor(user.points)) + ' tier';
  $('#profilePoints').textContent = (user.points || 0).toLocaleString();
  $('#profileJoined').textContent = formatDate(user.joined);
  $('#profileLastSpin').textContent = formatRelative(user.lastSpin);

  const streak = user.streak || 0;
  const streakEl = $('#profileStreak');
  if (streak > 0) {
    streakEl.classList.remove('hidden');
    streakEl.textContent = `🔥 ${streak}-day streak`;
  } else {
    streakEl.classList.add('hidden');
  }

  const info = nextTierInfo(user.points || 0);
  $('#profileNextTier').textContent = info.next;
  if (info.done) {
    $('#profileProgressText').textContent = 'Top tier reached';
    $('#profileProgressFill').style.width = '100%';
  } else {
    const span = info.target - info.start;
    const have = Math.max(0, (user.points || 0) - info.start);
    const pct  = Math.min(100, Math.round((have / span) * 100));
    $('#profileProgressText').textContent = `${have.toLocaleString()} / ${span.toLocaleString()}`;
    $('#profileProgressFill').style.width = pct + '%';
  }
}

function spinRow(item) {
  const ts = formatRelative(item.at);
  const label = escapeHtml(item.label || (item.points + ' pts'));
  const extra = item.streakBonus
    ? ` <span class="activity-note">+${item.streakBonus} streak</span>`
    : (item.bonus ? ` <span class="activity-note">+${item.bonus} tier</span>` : '');
  return `
    <li class="activity-row">
      <span class="activity-icon spin">◆</span>
      <span class="activity-main">Spin · ${label}${extra}</span>
      <span class="activity-amount pos">+${(item.total || 0).toLocaleString()}</span>
      <span class="activity-time">${escapeHtml(ts)}</span>
    </li>`;
}

function redemptionRow(item) {
  const ts = formatRelative(item.at);
  const net = -Math.abs(item.cost || 0) + (item.extraBonus || 0);
  const cls = net >= 0 ? 'pos' : 'neg';
  const sign = net >= 0 ? '+' : '';
  return `
    <li class="activity-row">
      <span class="activity-icon redeem">✦</span>
      <span class="activity-main">Redeem · ${escapeHtml(item.title || item.rewardId)}</span>
      <span class="activity-amount ${cls}">${sign}${net.toLocaleString()}</span>
      <span class="activity-time">${escapeHtml(ts)}</span>
    </li>`;
}

async function renderActivity() {
  const list = $('#profileActivity');
  list.innerHTML = '<li class="activity-empty">Loading activity…</li>';

  const [histRes, redRes] = await Promise.allSettled([api.history(), api.redemptions()]);
  const hist = histRes.status === 'fulfilled' ? (histRes.value.history || []) : [];
  const reds = redRes.status === 'fulfilled' ? (redRes.value.redemptions || []) : [];

  const items = [
    ...hist.map(h => ({ kind: 'spin',   at: h.at, data: h })),
    ...reds.map(r => ({ kind: 'redeem', at: r.at, data: r }))
  ].sort((a, b) => (b.at || 0) - (a.at || 0)).slice(0, 8);

  if (items.length === 0) {
    list.innerHTML = '<li class="activity-empty">No activity yet — spin the wheel to get started.</li>';
    return;
  }
  list.innerHTML = items.map(i =>
    i.kind === 'spin' ? spinRow(i.data) : redemptionRow(i.data)
  ).join('');
}

function render() {
  renderHeader();
  renderActivity();
}

export function initProfile() {
  registerView('profile', { onOpen: render });
}
