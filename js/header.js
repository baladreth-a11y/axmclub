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
  const ageOk = !!state.ageConfirmed;

  // Basic user action visibility
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

  // Nav visibility rules:
  // - Anonymous + age OK: show only Players (models roster).
  // - Registered supporters: show Players, Supporters, Marketplace.
  // - Registered models: show Players, Cam Room, Model dashboard.
  if (!user && ageOk) {
    setHidden('#navPlayers', false);
    setHidden('#navPlay', true);
    setHidden('#navCam', true);
    setHidden('#navMarketplace', true);
    setHidden('#navSupporters', true);
    setHidden('#navRoster', true);
    setHidden('#navModelLink', true);
  } else if (!user) {
    // Age not confirmed: keep defaults (layout/gate will hide most UI)
    setHidden('#navPlayers', true);
    setHidden('#navPlay', true);
    setHidden('#navCam', true);
    setHidden('#navMarketplace', true);
    setHidden('#navSupporters', true);
    setHidden('#navRoster', true);
    setHidden('#navModelLink', true);
  } else {
    // Registered user: show/hide based on accountType
    if (user.accountType === 'model') {
      setHidden('#navPlayers', false);
      setHidden('#navPlay', true);
      setHidden('#navCam', false);
      setHidden('#navMarketplace', true);
      setHidden('#navSupporters', true);
      setHidden('#navRoster', true);
      setHidden('#navModelLink', false);
    } else {
      // supporter or other
      setHidden('#navPlayers', false);
      setHidden('#navPlay', false);
      setHidden('#navCam', false);
      setHidden('#navMarketplace', false);
      setHidden('#navSupporters', false);
      setHidden('#navRoster', false);
      setHidden('#navModelLink', true);
    }
  }

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
