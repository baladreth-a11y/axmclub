// Model dashboard logic. Owns the four cards on /model.html:
//   1. Profile editor (display name, bio, brand color, socials)
//   2. Stats summary (passwords + offers counters)
//   3. Cam passwords manager (list / create / revoke)
//   4. Targeted offers inbox (list / accept / decline)
//
// Server-side authorization comes from Require-Model in server.ps1 —
// every endpoint here is gated on the signed-in user being a 'model'.
// Client-side, requireModelAccount() in layout.js bounces non-models
// to / before this module runs.
import { $, escapeHtml, formatRelative, formatDate } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';

const SOCIAL_KEYS = ['telegram','snap','webcam','fansite'];

let passwordsCache = [];
let offersCache    = [];

function setText(sel, value) {
  const el = $(sel);
  if (el) el.textContent = value;
}

// ---- Profile editor -------------------------------------------------
function fillProfileForm(user) {
  setText('#dashHello', `Welcome, ${user.name}.`);
  setText('#dashEmail', user.email);
  setText('#dashJoined', formatDate(user.joined));
  const f = $('#profileForm');
  if (!f) return;
  f.elements['name'].value       = user.name || '';
  f.elements['bio'].value        = user.bio || '';
  f.elements['brandColor'].value = user.brandColor || '#7c6cff';
  for (const k of SOCIAL_KEYS) {
    const input = f.elements[`social_${k}`];
    if (input) input.value = (user.socials && user.socials[k]) || '';
  }
  applyBrandPreview(user.brandColor);
}

function applyBrandPreview(color) {
  const sw = $('#brandSwatch');
  if (sw) sw.style.background = color || 'transparent';
  document.documentElement.style.setProperty('--model-brand', color || 'var(--accent)');
}

async function onProfileSubmit(e) {
  e.preventDefault();
  const fd = new FormData(e.target);
  const body = {
    name:       (fd.get('name') || '').toString().trim(),
    bio:        (fd.get('bio')  || '').toString(),
    brandColor: (fd.get('brandColor') || '').toString().trim(),
    socials: SOCIAL_KEYS.reduce((acc, k) => {
      acc[k] = (fd.get(`social_${k}`) || '').toString().trim();
      return acc;
    }, {})
  };
  try {
    const res = await api.modelUpdateProfile(body);
    store.set(s => ({ ...s, user: res.user }));
    fillProfileForm(res.user);
    toast('Profile saved.', 'success');
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ---- Stats ---------------------------------------------------------
async function refreshStats() {
  try {
    const s = await api.modelStats();
    setText('#statPwIssued',     s.passwordsIssued);
    setText('#statPwActive',     s.passwordsActive);
    setText('#statRedemptions',  s.totalRedemptions);
    setText('#statOffersTotal',  s.offersTotal);
    setText('#statOffersOpen',   s.offersPending);
    setText('#statOffersWon',    s.offersAccepted);
  } catch (err) {
    toast('Could not load stats: ' + err.message, 'error');
  }
}

// ---- Passwords -----------------------------------------------------
function passwordRow(p) {
  const redeemers = Array.isArray(p.redeemedBy) ? p.redeemedBy : [];
  const usesDisplay = p.uses > 0
    ? p.uses + ' left'
    : '<span class="muted">Revoked</span>';
  const redeemedDisplay = redeemers.length
    ? `${redeemers.length} redeem${redeemers.length === 1 ? '' : 's'}`
    : '<span class="muted">—</span>';
  return `
    <tr>
      <td><code>${escapeHtml(p.code)}</code></td>
      <td>${usesDisplay}</td>
      <td>${redeemedDisplay}</td>
      <td class="muted">${escapeHtml(p.note || '')}</td>
      <td class="dash-row-actions">
        <button class="btn btn-outline pw-revoke" data-code="${escapeHtml(p.code)}" ${p.uses === 0 ? 'disabled' : ''}>Revoke</button>
      </td>
    </tr>`;
}

function renderPasswords() {
  const tbody = $('#pwBody');
  if (!tbody) return;
  if (!passwordsCache.length) {
    tbody.innerHTML = '<tr><td colspan="5" class="dash-empty">No passwords yet. Issue your first code below.</td></tr>';
    return;
  }
  tbody.innerHTML = passwordsCache.map(passwordRow).join('');
}

async function refreshPasswords() {
  try {
    const { passwords } = await api.modelPasswords();
    passwordsCache = Array.isArray(passwords) ? passwords : [];
    renderPasswords();
  } catch (err) {
    passwordsCache = [];
    const tbody = $('#pwBody');
    if (tbody) tbody.innerHTML = `<tr><td colspan="5" class="dash-empty">${escapeHtml(err.message)}</td></tr>`;
  }
}

async function onCreatePassword(e) {
  e.preventDefault();
  const fd = new FormData(e.target);
  const code = (fd.get('password') || '').toString().toUpperCase().trim();
  const uses = parseInt(fd.get('uses'), 10) || 1;
  const note = (fd.get('note') || '').toString().trim();
  try {
    const res = await api.modelCreatePassword({ password: code, uses, note });
    e.target.reset();
    e.target.querySelector('input[name="uses"]').value = 5;
    toast(`Created ${res.password} (${res.uses} uses).`, 'success');
    await Promise.all([refreshPasswords(), refreshStats()]);
  } catch (err) {
    toast(err.message, 'error');
  }
}

async function onRevokePassword(code) {
  if (!confirm(`Revoke ${code}? It will stop granting passes immediately.`)) return;
  try {
    await api.modelRevokePassword(code);
    toast(`${code} revoked.`, 'success');
    await Promise.all([refreshPasswords(), refreshStats()]);
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ---- Offers --------------------------------------------------------
function offerRow(o) {
  const dateStr = formatRelative(o.at);
  const status = o.status || 'pending';
  return `
    <tr>
      <td class="muted" style="white-space:nowrap">${escapeHtml(dateStr)}</td>
      <td>
        <strong>${escapeHtml(o.fromName || o.from)}</strong>
        <div class="muted" style="font-size:11px">${escapeHtml(o.from)}</div>
      </td>
      <td class="offer-msg" title="${escapeHtml(o.message)}">${escapeHtml(o.message)}</td>
      <td><span class="dash-status ${escapeHtml(status)}">${escapeHtml(status)}</span></td>
      <td class="dash-row-actions">
        <button class="btn btn-primary offer-accept"  data-from="${escapeHtml(o.from)}" data-id="${escapeHtml(o.id)}" ${status === 'accepted' ? 'disabled' : ''}>Accept</button>
        <button class="btn btn-outline offer-decline" data-from="${escapeHtml(o.from)}" data-id="${escapeHtml(o.id)}" ${status === 'declined' ? 'disabled' : ''}>Decline</button>
      </td>
    </tr>`;
}

function renderOffers() {
  const tbody = $('#offersBody');
  if (!tbody) return;
  if (!offersCache.length) {
    tbody.innerHTML = '<tr><td colspan="5" class="dash-empty">No offers addressed to you yet.</td></tr>';
    return;
  }
  tbody.innerHTML = offersCache.map(offerRow).join('');
}

async function refreshOffers() {
  try {
    const { offers } = await api.modelOffers();
    offersCache = Array.isArray(offers) ? offers : [];
    renderOffers();
  } catch (err) {
    offersCache = [];
    const tbody = $('#offersBody');
    if (tbody) tbody.innerHTML = `<tr><td colspan="5" class="dash-empty">${escapeHtml(err.message)}</td></tr>`;
  }
}

async function respondToOffer(userEmail, offerId, status) {
  try {
    await api.modelRespondOffer({ userEmail, offerId, status });
    toast(`Offer ${status}.`, 'success');
    await Promise.all([refreshOffers(), refreshStats()]);
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ---- Init ----------------------------------------------------------
export async function initModelDashboard(user) {
  // The store user comes from /api/me; layout.js requires model
  // accountType before this runs. Hydrate the form from the snapshot
  // we were given, then refresh the cards in parallel.
  store.set({ user });
  fillProfileForm(user);

  $('#profileForm')?.addEventListener('submit', onProfileSubmit);

  // Live preview the brand color while the user types/picks.
  $('#profileForm')?.addEventListener('input', e => {
    if (e.target.name === 'brandColor') applyBrandPreview(e.target.value);
  });

  $('#newPasswordForm')?.addEventListener('submit', onCreatePassword);
  $('#pwBody')?.addEventListener('click', e => {
    const btn = e.target.closest('.pw-revoke');
    if (btn && !btn.disabled) onRevokePassword(btn.dataset.code);
  });

  $('#offersBody')?.addEventListener('click', e => {
    const accept = e.target.closest('.offer-accept');
    if (accept && !accept.disabled) {
      respondToOffer(accept.dataset.from, accept.dataset.id, 'accepted');
      return;
    }
    const decline = e.target.closest('.offer-decline');
    if (decline && !decline.disabled) {
      respondToOffer(decline.dataset.from, decline.dataset.id, 'declined');
    }
  });

  await Promise.all([refreshPasswords(), refreshOffers(), refreshStats()]);
}
