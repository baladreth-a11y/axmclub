import { $, $$ } from './util.js';

// view name -> optional onOpen hook
const hooks = new Map();

// Element that was focused before the modal opened — used to restore
// focus when the modal closes so keyboard users don't get dumped to
// the top of the page.
let previousFocus = null;

const FOCUSABLE_SEL =
  'input:not([disabled]), button:not([disabled]), a[href], textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

function activeViewFocusables() {
  const backdrop = $('#modalBackdrop');
  if (!backdrop || backdrop.classList.contains('hidden')) return [];
  const active = backdrop.querySelector('.modal-view:not(.hidden)');
  if (!active) return [];
  return $$(FOCUSABLE_SEL, active);
}

export function registerView(name, { onOpen } = {}) {
  if (onOpen) hooks.set(name, onOpen);
}

export function openModal(name) {
  // Remember the trigger element so focus can snap back on close.
  if (!previousFocus) previousFocus = document.activeElement;
  $('#modalBackdrop').classList.remove('hidden');
  switchView(name);
  // Autofocus the first useful field in the just-shown view after the
  // browser has painted it (so display:none -> visible has taken effect).
  requestAnimationFrame(() => {
    const fs = activeViewFocusables();
    // Skip the close button; prefer the first input/textarea/button inside the view.
    const target = fs.find(el => el.tagName !== 'BUTTON' || !el.classList.contains('modal-close')) || fs[0];
    if (target) target.focus();
  });
}

export function closeModal() {
  $('#modalBackdrop').classList.add('hidden');
  // Restore focus to whoever opened us.
  if (previousFocus && typeof previousFocus.focus === 'function') {
    try { previousFocus.focus(); } catch { /* element may have detached */ }
  }
  previousFocus = null;
}

export function switchView(name) {
  for (const el of $$('.modal-view')) {
    el.classList.toggle('hidden', el.dataset.view !== name);
  }
  const hook = hooks.get(name);
  if (hook) hook();
  // After a view swap (e.g. register -> login), move focus into the new one.
  requestAnimationFrame(() => {
    const fs = activeViewFocusables();
    const target = fs.find(el => el.tagName !== 'BUTTON' || !el.classList.contains('modal-close')) || fs[0];
    if (target) target.focus();
  });
}

export function initModal() {
  document.addEventListener('keydown', e => {
    const backdrop = $('#modalBackdrop');
    const isOpen = backdrop && !backdrop.classList.contains('hidden');
    if (!isOpen) return;

    if (e.key === 'Escape') { closeModal(); return; }

    // Focus trap: Tab/Shift+Tab cycles within the active view.
    if (e.key === 'Tab') {
      const fs = activeViewFocusables();
      if (fs.length === 0) return;
      const first = fs[0];
      const last  = fs[fs.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault(); last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault(); first.focus();
      }
    }
  });

  $('#modalBackdrop').addEventListener('click', e => {
    if (e.target.id === 'modalBackdrop') closeModal();
  });

  // Expose minimum for inline `onclick` in markup.
  window.closeModal = closeModal;
  window.switchView = switchView;
  window.openModal  = openModal;
}
