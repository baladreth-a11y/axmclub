import { $, escapeHtml } from './util.js';
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
  $('#widgetRank').textContent     = u ? formatRank(u.rank) : '—';
  $('#widgetLevel').textContent    = u ? (u.level || 0).toLocaleString() : '—';
  $('#widgetPoints').textContent   = u ? (u.points || 0).toLocaleString() : '—';
  $('#widgetTokens').textContent   = u ? (u.tokens || 0).toLocaleString() : '—';

  // Buttons are only useful when signed in.
  $('#widgetGetTokens').disabled = !u;
  $('#widgetMakeOffer').disabled = !u;
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
