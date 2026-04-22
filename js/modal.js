import { $, $$ } from './util.js';

// view name -> optional onOpen hook
const hooks = new Map();

export function registerView(name, { onOpen } = {}) {
  if (onOpen) hooks.set(name, onOpen);
}

export function openModal(name) {
  $('#modalBackdrop').classList.remove('hidden');
  switchView(name);
}

export function closeModal() {
  $('#modalBackdrop').classList.add('hidden');
}

export function switchView(name) {
  for (const el of $$('.modal-view')) {
    el.classList.toggle('hidden', el.dataset.view !== name);
  }
  const hook = hooks.get(name);
  if (hook) hook();
}

export function initModal() {
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') closeModal();
  });
  $('#modalBackdrop').addEventListener('click', e => {
    if (e.target.id === 'modalBackdrop') closeModal();
  });
  // Expose minimum for inline `onclick` in markup.
  window.closeModal = closeModal;
  window.switchView = switchView;
  window.openModal = openModal;
}
