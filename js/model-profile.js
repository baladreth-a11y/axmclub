// Public per-model profile view (m.html?model=<slug> or ?slug=<slug>).
//
// Fetches /api/models/:slug. The server gates the response:
//   * 401 (anonymous)  -> render a "sign in" CTA.
//   * 403 verify-email -> render a "verify your email" CTA.
//   * 404              -> render "not found".
//   * 200              -> render photo, bio, socials, gallery.
import { $, escapeHtml } from './util.js';
import { api } from './api.js';
import { toast , reportError} from './ui.js';
import { updateSEO } from './layout.js';
import { openCommunicatorWith } from './communicator.js';

const GENDER_LABELS = {
  male:         'Male',
  female:       'Female',
  crossdresser: 'Crossdresser',
  transsexual:  'Transsexual'
};

function getSlug() {
  try {
    const params = new URLSearchParams(window.location.search);
    return (params.get('model') || params.get('slug') || '').trim();
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
  if (s.telegram) items.push(`<a href="${escapeHtml(s.telegram)}" rel="noopener" target="_blank" data-kind="telegram" class="btn btn-outline m-social-link">Telegram</a>`);
  if (s.snap)     items.push(`<a href="${escapeHtml(s.snap)}"     rel="noopener" target="_blank" data-kind="snap"     class="btn btn-outline m-social-link">Snapchat</a>`);
  if (s.webcam)   items.push(`<a href="${escapeHtml(s.webcam)}"   rel="noopener" target="_blank" data-kind="webcam"   class="btn btn-primary m-social-link">Webcam</a>`);
  if (s.fansite)  items.push(`<a href="${escapeHtml(s.fansite)}"  rel="noopener" target="_blank" data-kind="fansite"  class="btn btn-outline m-social-link">OnlyFans</a>`);
  if (!items.length) return '';
  return `<div class="m-profile-socials">${items.join('')}</div>`;
}

function gallery(items) {
  if (!Array.isArray(items) || !items.length) {
    return '<p class="muted">No gallery photos yet.</p>';
  }
  return `<div class="m-profile-gallery">${items.map((g, index) => `
    <div class="gallery-item" data-index="${index}">
      <img src="${escapeHtml(g.url)}" alt="Model media visual" loading="lazy" />
      <div class="gallery-item-overlay">
        <span>🔍 View</span>
      </div>
    </div>`).join('')}</div>`;
}

let currentLightboxIndex = 0;
let lightboxItems = [];

function openLightbox(index, items) {
  currentLightboxIndex = index;
  lightboxItems = items;
  
  let overlay = $('#lightboxOverlay');
  if (!overlay) {
    overlay = document.createElement('div');
    overlay.id = 'lightboxOverlay';
    overlay.className = 'lightbox-overlay hidden';
    overlay.innerHTML = `
      <button class="lightbox-close" aria-label="Close lightbox">×</button>
      <button class="lightbox-nav lightbox-prev" aria-label="Previous image">‹</button>
      <div class="lightbox-content">
        <img id="lightboxImg" src="" alt="Gallery visual" />
        <div id="lightboxCaption" class="lightbox-caption"></div>
      </div>
      <button class="lightbox-nav lightbox-next" aria-label="Next image">›</button>
    `;
    document.body.appendChild(overlay);
    
    overlay.querySelector('.lightbox-close').addEventListener('click', closeLightbox);
    overlay.querySelector('.lightbox-prev').addEventListener('click', prevLightbox);
    overlay.querySelector('.lightbox-next').addEventListener('click', nextLightbox);
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay || e.target.classList.contains('lightbox-content')) {
        closeLightbox();
      }
    });
    
    document.addEventListener('keydown', handleLightboxKeydown);
  }
  
  overlay.classList.remove('hidden');
  document.body.classList.add('lightbox-open-body');
  updateLightbox();
}

function updateLightbox() {
  const img = $('#lightboxImg');
  const caption = $('#lightboxCaption');
  if (!img || !caption || !lightboxItems[currentLightboxIndex]) return;
  
  img.src = lightboxItems[currentLightboxIndex].url;
  caption.textContent = `Image ${currentLightboxIndex + 1} of ${lightboxItems.length}`;
}

function closeLightbox() {
  const overlay = $('#lightboxOverlay');
  if (overlay) {
    overlay.classList.add('hidden');
  }
  document.body.classList.remove('lightbox-open-body');
}

function prevLightbox() {
  if (!lightboxItems.length) return;
  currentLightboxIndex = (currentLightboxIndex - 1 + lightboxItems.length) % lightboxItems.length;
  updateLightbox();
}

function nextLightbox() {
  if (!lightboxItems.length) return;
  currentLightboxIndex = (currentLightboxIndex + 1) % lightboxItems.length;
  updateLightbox();
}

function handleLightboxKeydown(e) {
  const overlay = $('#lightboxOverlay');
  if (!overlay || overlay.classList.contains('hidden')) return;
  
  if (e.key === 'Escape') {
    closeLightbox();
  } else if (e.key === 'ArrowLeft') {
    prevLightbox();
  } else if (e.key === 'ArrowRight') {
    nextLightbox();
  }
}

function renderProfile(m) {
  const root = $('#mProfile');
  if (!root) return;
  
  updateSEO({
    title: `${m.name} — AxMclub.com Premium Companion`,
    description: m.bio || `Meet ${m.name}, an exclusive premium cam-room companion at AxMclub.com. View profiles, photos, and live sessions.`,
    keywords: `AxMclub, model, ${m.name}, cam, premium, companion`
  });
  
  const photo = m.photoUrl
    ? `<img class="m-profile-photo" src="${escapeHtml(m.photoUrl)}" alt="${escapeHtml(m.name)}" />`
    : `<span class="m-profile-photo m-profile-photo--initial">${escapeHtml((m.name || '?')[0].toUpperCase())}</span>`;
  const bio = m.bio ? `<p class="m-profile-bio">${escapeHtml(m.bio)}</p>` : '';
  const brandStyle = m.brandColor ? ` style="--model-brand: ${escapeHtml(m.brandColor)};"` : '';
  
  root.innerHTML = `
    <article class="m-profile-card"${brandStyle}>
      <header class="m-profile-head">
        <div class="m-avatar-container">
          ${photo}
          <div class="status-indicator-ring pulsing"></div>
          <span class="status-badge-text"><span class="status-dot"></span> Online</span>
        </div>
        
        <div class="m-profile-ident">
          <div class="m-title-row">
            <h1>${escapeHtml(m.name)}</h1>
            <span class="m-rank-badge" style="--rank-color: ${escapeHtml(m.brandColor || '#d4af6a')}">${escapeHtml(m.rank || 'Platinum')}</span>
          </div>
          
          <div class="m-meta-row">
            ${genderBadge(m.gender)}
            <span class="m-meta-item">✨ <b>${m.gallery ? m.gallery.length : 0}</b> Posts</span>
            <span class="m-meta-item">💖 <b>14.2k</b> Followers</span>
          </div>

          ${bio}

          <div class="m-action-buttons">
            <button id="btnProfileMsg" class="btn btn-primary m-btn-action"><svg class="m-btn-icon" viewBox="0 0 24 24" width="18" height="18"><path d="M20 2H4c-1.1 0-1.99.9-1.99 2L2 22l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zM6 9h12v2H6V9zm8 5H6v-2h8v2zm4-6H6V6h12v2z" fill="currentColor"/></svg> Message</button>
            <button id="btnProfileTip" class="btn btn-accent m-btn-action"><svg class="m-btn-icon" viewBox="0 0 24 24" width="18" height="18"><path d="M21.41 11.58l-9-9C12.05 2.22 11.55 2 11 2H4c-1.1 0-2 .9-2 2v7c0 .55.22 1.05.59 1.42l9 9c.36.36.86.58 1.41.58.55 0 1.05-.22 1.41-.59l7-7c.37-.36.59-.86.59-1.41 0-.55-.23-1.06-.59-1.42zM5.5 8C4.67 8 4 7.33 4 6.5S4.67 5 5.5 5 7 5.67 7 6.5 6.33 8 5.5 8z" fill="currentColor"/></svg> Tip Host</button>
          </div>

          ${socialLinks(m.socials)}
        </div>
      </header>
      
      <section class="m-profile-section">
        <h2 class="gallery-title">Exclusive Gallery</h2>
        ${gallery(m.gallery)}
      </section>
    </article>`;
    
  // Wire Action Buttons
  $('#btnProfileMsg')?.addEventListener('click', () => {
    openCommunicatorWith(m.email, m.name);
  });
  
  $('#btnProfileTip')?.addEventListener('click', () => {
    if (window.openModal) {
      window.openModal('tokens');
    } else {
      toast('Please use the dynamic shop to get tokens!', 'info');
    }
  });

  // Wire Gallery Lightbox click handlers
  root.querySelectorAll('.gallery-item').forEach(item => {
    item.addEventListener('click', () => {
      const index = parseInt(item.dataset.index);
      if (m.gallery && m.gallery[index]) {
        openLightbox(index, m.gallery);
      }
    });
  });
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
