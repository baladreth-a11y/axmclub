// Email verification UX. When a signed-in user has emailVerified ===
// false, we surface a small banner immediately under the navbar with a
// "Resend verification email" button. The /api/verify/start endpoint
// is idempotent (overwrites any prior unused token) so spamming it is
// fine.
//
// On successful confirm the server redirects back to /?verified=1; we
// look for that query param on load and flash a green toast.
import { $ } from './util.js';
import { store } from './store.js';
import { api } from './api.js';
import { toast } from './ui.js';

let banner = null;

function ensureBanner() {
  if (banner) return banner;
  banner = document.createElement('div');
  banner.id = 'verifyBanner';
  banner.className = 'verify-banner hidden';
  banner.innerHTML = `
    <div class="container verify-banner-inner">
      <span>Verify your email to view full model profiles.</span>
      <button id="verifyResendBtn" class="btn btn-outline" type="button">Send verification email</button>
    </div>`;
  // Insert after the navbar so it sits in the natural flow.
  const nav = document.querySelector('.navbar');
  if (nav && nav.parentNode) {
    nav.insertAdjacentElement('afterend', banner);
  } else {
    document.body.insertBefore(banner, document.body.firstChild);
  }
  banner.querySelector('#verifyResendBtn').addEventListener('click', resend);
  return banner;
}

async function resend() {
  try {
    const res = await api.verifyStart();
    if (res.alreadyVerified) {
      toast('Your email is already verified.', 'success');
    } else {
      toast('Verification email sent. Check your inbox.', 'success');
    }
  } catch (err) {
    toast(err.message, 'error');
  }
}

function render(state) {
  const u = state.user;
  const showBanner = !!u && u.emailVerified === false;
  if (!showBanner) {
    if (banner) banner.classList.add('hidden');
    return;
  }
  ensureBanner().classList.remove('hidden');
}

function flashIfJustVerified() {
  try {
    const params = new URLSearchParams(window.location.search);
    if (params.get('verified') === '1') {
      toast('Email verified \u2014 welcome to the club.', 'success');
      // Clean up the URL so a refresh doesn't re-flash.
      params.delete('verified');
      const q = params.toString();
      const newUrl = window.location.pathname + (q ? '?' + q : '') + window.location.hash;
      window.history.replaceState(null, '', newUrl);
    }
  } catch { /* ignore */ }
}

export function initVerifyBanner() {
  flashIfJustVerified();
  render(store.get());
  store.subscribe(render);
}
