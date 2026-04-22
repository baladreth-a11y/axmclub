import { $, escapeHtml } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { openModal } from './modal.js';

function tierBadgeClass(tier) {
  const t = (tier || '').toLowerCase();
  if (t === 'platinum') return 'badge badge-accent';
  if (t === 'gold')     return 'badge badge-gold';
  return 'badge badge-muted';
}

function cardHtml(r) {
  const disabled = !r.available;
  let lockReason = '';
  if (!store.get().user) {
    lockReason = 'Sign in to redeem';
  } else if (!r.tierOk) {
    lockReason = `Requires ${r.minTier}`;
  } else if (!r.canAfford) {
    lockReason = 'Not enough points';
  }
  const btnLabel = disabled
    ? (lockReason || 'Unavailable')
    : `Redeem · ${r.cost.toLocaleString()} pts`;

  return `
    <article class="catalog-card${disabled ? ' is-locked' : ''}" data-reward-id="${escapeHtml(r.id)}">
      <header class="catalog-head">
        <h3>${escapeHtml(r.title)}</h3>
        <span class="${tierBadgeClass(r.minTier)}">${escapeHtml(r.minTier)}</span>
      </header>
      <p class="catalog-desc">${escapeHtml(r.description)}</p>
      <footer class="catalog-foot">
        <span class="catalog-cost">${r.cost.toLocaleString()}<small>pts</small></span>
        <button
          class="btn ${disabled ? 'btn-outline' : 'btn-primary'} catalog-redeem"
          data-reward-id="${escapeHtml(r.id)}"
          ${disabled ? 'disabled' : ''}>
          ${escapeHtml(btnLabel)}
        </button>
      </footer>
    </article>`;
}

function renderCatalog(rewards) {
  $('#catalogGrid').innerHTML = rewards.map(cardHtml).join('');
}

export async function refreshRewards() {
  try {
    const data = await api.rewards();
    store.set({ rewards: data.rewards || [] });
  } catch {
    $('#catalogGrid').innerHTML =
      '<p class="lb-empty">Could not load the catalog.</p>';
  }
}

async function redeem(rewardId, reward) {
  const nice = reward ? reward.title : 'this reward';
  if (!confirm(`Redeem "${nice}" for ${reward.cost.toLocaleString()} pts?`)) return;
  try {
    const res = await api.redeem(rewardId);
    store.set(s => ({ ...s, user: res.user }));
    refreshRewards();
    // Let other modules know
    document.dispatchEvent(new CustomEvent('axm:redeem-complete', { detail: res }));
    toast(res.redemption.message || 'Reward claimed!', 'success');
  } catch (err) {
    if (err.status === 401) {
      openModal('login');
      toast('Sign in to redeem.');
    } else {
      toast(err.message, 'error');
    }
  }
}

export function initRewards() {
  // Re-render whenever the store changes (user balance, rewards list).
  store.subscribe(state => {
    if (state.rewards) renderCatalog(state.rewards);
  });

  // Event delegation — one listener, keeps working as cards re-render.
  $('#catalogGrid').addEventListener('click', e => {
    const btn = e.target.closest('.catalog-redeem');
    if (!btn || btn.disabled) return;
    const id = btn.dataset.rewardId;
    const reward = (store.get().rewards || []).find(r => r.id === id);
    if (reward) redeem(id, reward);
  });

  // Keep catalog fresh when relevant things happen.
  document.addEventListener('axm:spin-complete', refreshRewards);

  // If the user changes (login/logout), balance + tierOk/canAfford change.
  let prevUserEmail = undefined;
  store.subscribe(state => {
    const email = state.user ? state.user.email : null;
    if (email !== prevUserEmail) {
      prevUserEmail = email;
      refreshRewards();
    }
  });
}
