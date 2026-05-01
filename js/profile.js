import { $, escapeHtml, tierFor, nextTierInfo, formatDate, formatRelative } from './util.js';
import { store } from './store.js';
import { api } from './api.js';
import { registerView } from './modal.js';

function setText(sel, value) {
  const el = $(sel);
  if (el) el.textContent = value;
}

function setHidden(sel, hidden) {
  const el = $(sel);
  if (el) el.classList.toggle('hidden', !!hidden);
}

function renderHeader() {
  const { user } = store.get();
  if (!user) return;

  const points = user.points || 0;
  const tokens = user.tokens || 0;
  const level = user.level || (points + tokens);
  const rank = (user.rank || '').trim() || 'Unranked';
  const tier = user.tier || tierFor(points);

  setText('#profileAvatar', (user.name[0] || 'U').toUpperCase());
  setText('#profileName', user.name);
  setText('#profileEmail', user.email);
  setText('#profileTier', tier + ' tier');
  setText('#profileRank', rank);
  setText('#profileLevel', level.toLocaleString());
  setText('#profilePoints', points.toLocaleString());
  setText('#profileTokens', tokens.toLocaleString());
  setText('#profileJoined', formatDate(user.joined));
  setText('#profileLastSpin', formatRelative(user.lastSpin));

  const verifiedEl = $('#profileVerified');
  if (verifiedEl) {
    const verified = user.emailVerified === true;
    verifiedEl.textContent = verified ? 'Email verified' : 'Email unverified';
    verifiedEl.classList.toggle('badge-gold', verified);
    verifiedEl.classList.toggle('badge-muted', !verified);
  }

  const streak = user.streak || 0;
  if (streak > 0) {
    setHidden('#profileStreak', false);
    setText('#profileStreak', `🔥 ${streak}-day streak`);
  } else {
    setHidden('#profileStreak', true);
  }

  const info = nextTierInfo(points);
  setText('#profileNextTier', info.next);
  if (info.done) {
    setText('#profileProgressText', 'Top tier reached');
    const fill = $('#profileProgressFill');
    if (fill) fill.style.width = '100%';
  } else {
    const span = info.target - info.start;
    const have = Math.max(0, points - info.start);
    const pct  = Math.min(100, Math.round((have / span) * 100));
    setText('#profileProgressText', `${have.toLocaleString()} / ${span.toLocaleString()}`);
    const fill = $('#profileProgressFill');
    if (fill) fill.style.width = pct + '%';
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
