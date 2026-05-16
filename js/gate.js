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

// ---- Focus trap ---------------------------------------------------------
// While the gate is visible and focused, Tab/Shift+Tab cycle within it so
// keyboard users cannot accidentally move focus to blurred background content.
const FOCUSABLE = 'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])';

function getFocusables(gate) {
  return Array.from(gate.querySelectorAll(FOCUSABLE)).filter(el => {
    return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
  });
}

function handleFocusTrap(e) {
  const gate = $('#gate');
  if (!gate || gate.classList.contains('hidden')) return;
  if (e.key !== 'Tab') return;
  const focusables = getFocusables(gate);
  if (!focusables.length) return;
  const first = focusables[0];
  const last  = focusables[focusables.length - 1];
  if (e.shiftKey) {
    if (document.activeElement === first) { e.preventDefault(); last.focus(); }
  } else {
    if (document.activeElement === last)  { e.preventDefault(); first.focus(); }
  }
}

let trapAttached = false;
function attachTrap() {
  if (trapAttached) return;
  document.addEventListener('keydown', handleFocusTrap);
  trapAttached = true;
}

// Move focus to the first interactive button inside the active gate stage.
function focusGate() {
  const gate = $('#gate');
  if (!gate || gate.classList.contains('hidden')) return;
  requestAnimationFrame(() => {
    const firstBtn = gate.querySelector('[data-stage]:not(.hidden) button:not([disabled]), [data-stage]:not(.hidden) a[href]');
    if (firstBtn) firstBtn.focus();
  });
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

  // If age is confirmed AND user is signed in, hide the gate entirely.
  if (ageOk && signedIn) {
    gate.classList.add('hidden');
    return;
  }

  // Otherwise, the gate must be visible.
  gate.classList.remove('hidden');

  const ageStage  = gate.querySelector('[data-stage="age"]');
  const authStage = gate.querySelector('[data-stage="auth"]');

  if (!ageOk) {
    // Stage A: Age verification
    if (ageStage)  ageStage.classList.remove('hidden');
    if (authStage) authStage.classList.add('hidden');
  } else {
    // Stage B: Auth prompt
    if (ageStage)  ageStage.classList.add('hidden');
    if (authStage) authStage.classList.remove('hidden');
  }

  focusGate();
}

function onAgeConfirm() {
  saveAgeConfirmed();
  render(store.get());
}

export function initGate() {
  // HTML ships with both gate classes already applied so we don't flash
  // unauthenticated content. This call reconciles with actual state.
  attachTrap();
  render(store.get());
  store.subscribe(render);

  const yesBtn = $('#gateAgeYes');
  if (yesBtn) yesBtn.addEventListener('click', onAgeConfirm);
}
