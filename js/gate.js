import { $ } from './util.js';
import { store } from './store.js';

function render(state) {
  const signedOut = !state.user;
  document.body.classList.toggle('is-gated', signedOut);
  $('#gate').classList.toggle('hidden', !signedOut);
}

export function initGate() {
  // Ensure gate is visible until the store gets hydrated with user state.
  document.body.classList.add('is-gated');
  $('#gate').classList.remove('hidden');

  store.subscribe(render);
  render(store.get());
}
