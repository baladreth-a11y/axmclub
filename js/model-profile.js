// Public per-model profile view (m.html?slug=<slug>).
//
// Fetches /api/models/:slug. The server gates the response:
//   * 401 (anonymous)  -> render a "sign in" CTA.
//   * 403 verify-email -> render a "verify your email" CTA.
//   * 404              -> render "not found".
//   * 200              -> render photo, bio, socials, gallery.
import { $, escapeHtml } from './util.js';
import { api } from './api.js';
import { toast , reportError} from './ui.js';

const GENDER_LABELS = {
  male:         'Male',
  female:       'Female',
  crossdresser: 'Crossdresser',
  transsexual:  'Transsexual'
};

function getSlug() {
  try {
    const params = new URLSearchParams(window.location.search);
    return (params.get('slug') || '').trim();
  } catch { return ''; }
}

function genderBadge(gender) {
  const safe = (gender || '').toLowerCase();
  if (!GENDER_LABELS[safe]) return '';
  return `<span class="badge badge-${safe}">${GENDER_LABELS[safe]}</span>`;
}

function socialLinks(s) {
  if (!s) return '';
  const items = [];
  if (s.telegram) items.push(`<a href="${escapeHtml(s.telegram)}" rel="noopener" data-kind="telegram" class="btn btn-outline">Telegram</a>`);
  if (s.snap)     items.push(`<a href="${escapeHtml(s.snap)}"     rel="noopener" data-kind="snap"     class="btn btn-outline">Snap</a>`);
  if (s.webcam)   items.push(`<a href="${escapeHtml(s.webcam)}"   rel="noopener" data-kind="webcam"   class="btn btn-primary">Webcam</a>`);
  if (s.fansite)  items.push(`<a href="${escapeHtml(s.fansite)}"  rel="noopener" data-kind="fansite"  class="btn btn-outline">Fansite</a>`);
  if (!items.length) return '';
  return `<div class="m-profile-socials">${items.join('')}</div>`;
}

function gallery(items) {
  if (!Array.isArray(items) || !items.length) {
    return '<p class="muted">No gallery photos yet.</p>';
  }
  return `<div class="m-profile-gallery">${items.map(g => `
    <a href="${escapeHtml(g.url)}" target="_blank" rel="noopener">
      <img src="${escapeHtml(g.url)}" alt="" loading="lazy" />
    </a>`).join('')}</div>`;
}

function renderProfile(m) {
  const root = $('#mProfile');
  if (!root) return;
  document.title = `${m.name} — AxMclub.com`;
  const photo = m.photoUrl
    ? `<img class="m-profile-photo" src="${escapeHtml(m.photoUrl)}" alt="${escapeHtml(m.name)}" />`
    : `<span class="m-profile-photo m-profile-photo--initial">${escapeHtml((m.name || '?')[0].toUpperCase())}</span>`;
  const bio = m.bio ? `<p class="m-profile-bio">${escapeHtml(m.bio)}</p>` : '';
  const brandStyle = m.brandColor ? ` style="--model-brand: ${escapeHtml(m.brandColor)};"` : '';
  root.innerHTML = `
    <article class="m-profile-card"${brandStyle}>
      <header class="m-profile-head">
        ${photo}
        <div class="m-profile-ident">
          <span class="eyebrow">AxMcamPlayer</span>
          <h1>${escapeHtml(m.name)}</h1>
          ${genderBadge(m.gender)}
          ${bio}
          ${socialLinks(m.socials)}
        </div>
      </header>
      <section class="m-profile-section">
        <h2>Gallery</h2>
        ${gallery(m.gallery)}
      </section>
    </article>`;
}

function renderSignInPrompt() {
  const root = $('#mProfile');
  if (!root) return;
  root.innerHTML = `
    <div class="m-profile-gate">
      <span class="eyebrow">Members only</span>
      <h1>Sign in to view this profile</h1>
      <p class="muted">Free to join \u2014 takes 10 seconds. After signing in, confirm your email to view full model profiles.</p>
      <div class="m-profile-gate-actions">
        <button class="btn btn-primary btn-lg" onclick="openModal('register')">Create free account</button>
        <button class="btn btn-outline btn-lg" onclick="openModal('login')">Sign in</button>
        <a href="/" class="btn btn-ghost btn-lg">Back to gallery</a>
      </div>
    </div>`;
}

function renderVerifyPrompt() {
  const root = $('#mProfile');
  if (!root) return;
  root.innerHTML = `
    <div class="m-profile-gate">
      <span class="eyebrow">One step left</span>
      <h1>Verify your email to view this profile</h1>
      <p class="muted">We sent a confirmation link to your email when you signed up. Click it to unlock model profiles.</p>
      <div class="m-profile-gate-actions">
        <button id="mResendBtn" class="btn btn-primary btn-lg">Resend verification email</button>
        <a href="/" class="btn btn-outline btn-lg">Back to gallery</a>
      </div>
    </div>`;
  $('#mResendBtn')?.addEventListener('click', async () => {
    try {
      const res = await api.verifyStart();
      toast(res.alreadyVerified ? 'Already verified.' : 'Verification email sent.', 'success');
    } catch (err) {
      reportError(err);
    }
  });
}

function renderNotFound() {
  const root = $('#mProfile');
  if (!root) return;
  root.innerHTML = `
    <div class="m-profile-gate">
      <span class="eyebrow">Not found</span>
      <h1>Model not found</h1>
      <p class="muted">This profile may have been removed or never existed.</p>
      <div class="m-profile-gate-actions">
        <a href="/" class="btn btn-primary btn-lg">Back to gallery</a>
      </div>
    </div>`;
}

export async function initModelProfile() {
  const slug = getSlug();
  if (!slug) {
    renderNotFound();
    return;
  }
  try {
    const res = await api.modelBySlug(slug);
    if (res && res.model) {
      renderProfile(res.model);
    } else {
      renderNotFound();
    }
  } catch (err) {
    if (err.status === 401) {
      renderSignInPrompt();
    } else if (err.status === 403 && err.data && err.data.reason === 'verify-email') {
      renderVerifyPrompt();
    } else if (err.status === 404) {
      renderNotFound();
    } else {
      const root = $('#mProfile');
      if (root) {
        root.innerHTML = `<p class="lb-empty">Could not load profile: ${escapeHtml(err.message)}</p>`;
      }
    }
  }
}
