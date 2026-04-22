import { $, $$, tierFor } from './util.js';
import { store } from './store.js';

function render(state) {
  const user = state.user;
  const chip = $('#userChip');
  const loginBtn = $('#openLogin');
  const registerBtn = $('#openRegister');

  if (user) {
    chip.classList.remove('hidden');
    loginBtn.classList.add('hidden');
    registerBtn.classList.add('hidden');
    $('#userName').textContent = user.name;
    $('#userInitial').textContent = (user.name[0] || 'U').toUpperCase();
  } else {
    chip.classList.add('hidden');
    loginBtn.classList.remove('hidden');
    registerBtn.classList.remove('hidden');
  }

  const points = user ? user.points : 0;
  const tier = user ? (user.tier || tierFor(points)) : null;
  $('#pointsValue').textContent = points.toLocaleString();
  $('#tierBadge').textContent = user ? `${tier} tier` : '— Not a member —';

  const tierKey = (tier || tierFor(points)).toLowerCase();
  for (const el of $$('.tier')) {
    el.classList.toggle('tier-highlight', el.dataset.tier === tierKey);
  }
}

export function initHeader() {
  render(store.get());
  store.subscribe(render);
}
