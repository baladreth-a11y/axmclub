import { $ } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast , reportError} from './ui.js';
import { openModal, closeModal, registerView } from './modal.js';

let pendingSource = 'welcome';

function setStepState(id, done) {
  const el = $('#' + id);
  if (!el) return;
  el.classList.toggle('is-done', !!done);
}

function render() {
  const { user } = store.get();
  if (!user) return;

  const name = user.name || 'there';
  const title = $('#onboardingTitle');
  const intro = $('#onboardingIntro');
  if (title) title.textContent = pendingSource === 'login' ? `Welcome back, ${name}` : `Welcome, ${name}`;
  if (intro) {
    intro.textContent = user.emailVerified === false
      ? 'Start with email verification so member-only model profiles unlock properly.'
      : 'Your account is ready. Here are the fastest ways to get value from the club.';
  }

  setStepState('onboardingStepAccount', true);
  setStepState('onboardingStepVerify', user.emailVerified !== false);
  setStepState('onboardingStepSpin', !!user.lastSpin);
  setStepState('onboardingStepExplore', false);

  const verifyBtn = $('#onboardingVerifyBtn');
  if (verifyBtn) {
    verifyBtn.hidden = user.emailVerified !== false;
    verifyBtn.disabled = false;
    verifyBtn.textContent = 'Send verification email';
  }
}

async function resendVerification() {
  const btn = $('#onboardingVerifyBtn');
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Sending...';
  }
  try {
    const res = await api.verifyStart();
    toast(res.alreadyVerified ? 'Your email is already verified.' : 'Verification email sent. Check your inbox.', 'success');
  } catch (err) {
    reportError(err);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Send verification email';
    }
  }
}

export function showOnboarding(source = 'welcome') {
  pendingSource = source;
  openModal('onboarding');
}

export function initOnboarding() {
  registerView('onboarding', { onOpen: render });
  store.subscribe(() => {
    const backdrop = $('#modalBackdrop');
    const active = backdrop && !backdrop.classList.contains('hidden') &&
      backdrop.querySelector('.modal-view[data-view="onboarding"]:not(.hidden)');
    if (active) render();
  });

  const verifyBtn = $('#onboardingVerifyBtn');
  if (verifyBtn) verifyBtn.addEventListener('click', resendVerification);

  const doneBtn = $('#onboardingDoneBtn');
  if (doneBtn) doneBtn.addEventListener('click', closeModal);
}
