import { $, $$, tierFor } from './util.js';
import { store } from './store.js';

// All DOM writes are null-safe: a few of these IDs (#pointsValue, #tierBadge)
// were moved into the stats widget over the lifetime of the project. Treat
// any missing element as a no-op rather than letting a TypeError propagate
// out of the store subscriber and break unrelated UI flows (notably: the
// auth modal's closeModal() after a successful register).
function setText(sel, value) {
  const el = $(sel);
  if (el) el.textContent = value;
}
function setHidden(sel, hidden) {
  const el = $(sel);
  if (el) el.classList.toggle('hidden', !!hidden);
}

function render(state) {
  const user = state.user;

  if (user) {
    setHidden('#userChip',     false);
    setHidden('#openLogin',    true);
    setHidden('#openRegister', true);
    setText('#userName',    user.name);
    setText('#userInitial', (user.name[0] || 'U').toUpperCase());
  } else {
    setHidden('#userChip',     true);
    setHidden('#openLogin',    false);
    setHidden('#openRegister', false);
  }

  // "Model dashboard" nav link is hidden by default and revealed only when
  // the signed-in user has accountType == 'model'. Server enforces the same
  // rule on every /api/model/* call.
  const showModelLink = !!user && user.accountType === 'model';
  setHidden('#navModelLink', !showModelLink);

  const points = user ? user.points : 0;
  const tier = user ? (user.tier || tierFor(points)) : null;
  setText('#pointsValue', points.toLocaleString());
  setText('#tierBadge',   user ? `${tier} tier` : '— Not a member —');

  const tierKey = (tier || tierFor(points)).toLowerCase();
  for (const el of $$('.tier')) {
    el.classList.toggle('tier-highlight', el.dataset.tier === tierKey);
  }
}

export function initHeader() {
  render(store.get());
  store.subscribe(render);
}
