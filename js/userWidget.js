import { $, escapeHtml, nextTierInfo } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast , reportError} from './ui.js';
import { openModal, closeModal } from './modal.js';

function formatRank(rank) {
  if (!rank) return 'Unranked';
  return rank;
}

function render(state) {
  const u = state.user;
  const guestState = $('#widgetGuestState');
  const userState = $('#widgetUserState');

  if (u) {
    if (guestState) guestState.classList.add('hidden');
    if (userState) userState.classList.remove('hidden');

    const rankEl = $('#widgetRank');
    const levelEl = $('#widgetLevel');
    const pointsEl = $('#widgetPoints');
    const tokensEl = $('#widgetTokens');

    if (rankEl) rankEl.textContent = formatRank(u.rank);
    if (levelEl) levelEl.textContent = (u.level || 0).toLocaleString();
    if (pointsEl) pointsEl.textContent = (u.points || 0).toLocaleString();
    if (tokensEl) tokensEl.textContent = (u.tokens || 0).toLocaleString();

    // Animate prestige circular gauge
    const points = u.points || 0;
    const progress = nextTierInfo(points);
    let pct = 0;
    if (progress.done) {
      pct = 100;
    } else {
      const range = progress.target - progress.start;
      const done = points - progress.start;
      pct = Math.min(100, Math.max(0, Math.floor((done / range) * 100)));
    }

    const fillEl = $('#widgetDialFill');
    const percentEl = $('#widgetProgressPercent');
    if (percentEl) percentEl.textContent = `${pct}%`;
    if (fillEl) {
      const offset = 251.2 - (251.2 * pct) / 100;
      fillEl.style.strokeDashoffset = offset;
    }

    const getTokensBtn = $('#widgetGetTokens');
    const makeOfferBtn = $('#widgetMakeOffer');
    if (getTokensBtn) getTokensBtn.disabled = false;
    if (makeOfferBtn) makeOfferBtn.disabled = false;
  } else {
    if (guestState) guestState.classList.remove('hidden');
    if (userState) userState.classList.add('hidden');
  }
}

async function onBuyTokens(e) {
  e.preventDefault();
  const fd = new FormData(e.target);
  const amount = parseInt(fd.get('amount'), 10);
  try {
    const res = await api.buyTokens(amount);
    store.set(s => ({ ...s, user: res.user }));
    closeModal();
    toast(`Added ${res.bought.toLocaleString()} tokens to your account.`, 'success');
  } catch (err) {
    reportError(err);
  }
}

async function onSubmitOffer(e) {
  e.preventDefault();
  const fd = new FormData(e.target);
  try {
    await api.makeOffer({
      target:  fd.get('target')  || '',
      message: fd.get('message') || ''
    });
    closeModal();
    e.target.reset();
    toast('Offer sent. The host team will review it.', 'success');
  } catch (err) {
    reportError(err);
  }
}

export function initUserWidget() {
  render(store.get());
  store.subscribe(render);

  $('#widgetGetTokens').addEventListener('click', () => {
    if (!store.get().user) return;
    openModal('tokens');
  });
  $('#widgetMakeOffer').addEventListener('click', () => {
    if (!store.get().user) return;
    openModal('offer');
  });

  $('#tokensForm').addEventListener('submit', onBuyTokens);
  $('#offerForm').addEventListener('submit', onSubmitOffer);
}
