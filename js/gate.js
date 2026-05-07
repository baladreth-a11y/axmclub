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

  // Publish age state into the shared store so other modules can react.
  const _prev = store.get();
  try {
    if (_prev.ageConfirmed !== ageOk) { store.set({ ageConfirmed: ageOk }); }
  } catch {}

  // Body classes:
  //   is-age-gated = age not confirmed (full blur of every section)
  //   is-gated     = age not confirmed (locks interaction until age is OK)
  //   is-anon      = signed out (regardless of age) so signed-in-only
  //                  widgets like the top-strip can hide themselves with
  //                  a single CSS rule. The model gallery itself stays
  //                  visible to anonymous visitors after age gate.
  document.body.classList.toggle('is-age-gated', !ageOk);
  document.body.classList.toggle('is-gated',     !ageOk);
  document.body.classList.toggle('is-anon',      !signedIn);

  const gate = $('#gate');
  if (!gate) return;
  // After age confirmation, dismiss the gate entirely. Sign-in is
  // surfaced via the navbar buttons and the verify-banner, not by a
  // hard wall in front of the page.
  gate.classList.toggle('hidden', ageOk);
  if (ageOk) return;

  const ageStage  = gate.querySelector('[data-stage="age"]');
  const authStage = gate.querySelector('[data-stage="auth"]');
  if (ageStage)  ageStage.classList.remove('hidden');
  if (authStage) authStage.classList.add('hidden');
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
