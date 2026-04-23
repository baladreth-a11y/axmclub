import { $ } from './util.js';
import { store } from './store.js';

const AGE_KEY = 'axm.ageConfirmed';
function ageConfirmed() {
  try { return localStorage.getItem(AGE_KEY) === '1'; }
  catch { return false; }
}
function saveAgeConfirmed() {
  try { localStorage.setItem(AGE_KEY, '1'); } catch { /* ignore */ }
}

function render(state) {
  const signedIn = !!state.user;
  const ageOk    = ageConfirmed();

  // Body classes:
  //   is-gated     = signed out  (locks interaction)
  //   is-age-gated = signed out AND age not confirmed (adds blur)
  document.body.classList.toggle('is-gated',     !signedIn);
  document.body.classList.toggle('is-age-gated', !signedIn && !ageOk);

  const gate = $('#gate');
  gate.classList.toggle('hidden', signedIn);
  if (signedIn) return;

  const ageStage  = gate.querySelector('[data-stage="age"]');
  const authStage = gate.querySelector('[data-stage="auth"]');
  ageStage.classList.toggle('hidden',  ageOk);
  authStage.classList.toggle('hidden', !ageOk);
}

function onAgeConfirm() {
  saveAgeConfirmed();
  render(store.get());
}

export function initGate() {
  // HTML ships with both gate classes already applied so we don't flash
  // unauthenticated content. This call reconciles with actual state.
  render(store.get());
  store.subscribe(render);

  const yesBtn = $('#gateAgeYes');
  if (yesBtn) yesBtn.addEventListener('click', onAgeConfirm);
}
