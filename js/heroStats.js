import { $ } from './util.js';
import { store } from './store.js';

function render(state) {
  $('#statMembers').textContent = (state.stats.members || 0).toLocaleString();
  $('#statSpins').textContent = (state.stats.spins || 0).toLocaleString();
}

export function initHeroStats() {
  render(store.get());
  store.subscribe(render);
}
