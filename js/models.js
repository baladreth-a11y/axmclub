// Public model gallery. Renders into any `#modelsGrid` placeholder on
// the page. The cards are public (anyone with confirmed age can see
// them); clicking a card navigates to /model.html?slug=<slug>, where
// the dashboard module handles the verified-only profile detail view.
import { $, escapeHtml } from './util.js';
import { api } from './api.js';

const GENDER_LABELS = {
  male:         'Male',
  female:       'Female',
  crossdresser: 'Crossdresser',
  transsexual:  'Transsexual'
};

function genderBadge(gender, accountType) {
  let badges = '';
  if (gender) {
    const safe = String(gender).toLowerCase();
    if (GENDER_LABELS[safe]) {
      badges += `<span class="badge badge-${safe}">${GENDER_LABELS[safe]}</span>`;
    }
  }
  return badges;
}

function brandStyle(color) {
  if (!color) return '';
  // Pass through; CSS validates with attribute selector or just lets
  // any string through (we already validated server-side).
  return `style="--model-brand: ${escapeHtml(color)};"`;
}

function socialLinks(s) {
  if (!s) return '';
  const items = [];
  if (s.telegram) items.push(`<a href="${escapeHtml(s.telegram)}" rel="noopener" data-kind="telegram">Telegram</a>`);
  if (s.snap)     items.push(`<a href="${escapeHtml(s.snap)}"     rel="noopener" data-kind="snap">Snap</a>`);
  if (s.webcam)   items.push(`<a href="${escapeHtml(s.webcam)}"   rel="noopener" data-kind="webcam">Webcam</a>`);
  if (s.fansite)  items.push(`<a href="${escapeHtml(s.fansite)}"  rel="noopener" data-kind="fansite">Fansite</a>`);
  if (!items.length) return '';
  return `<div class="model-socials">${items.join('')}</div>`;
}

function modelCard(m) {
  const initial = (m.name || '?')[0].toUpperCase();
  const photo = m.photoUrl
    ? `<span class="model-photo model-photo--cover" style="background-image: url('${escapeHtml(m.photoUrl)}')"></span>`
    : `<span class="model-photo model-photo--initial">${escapeHtml(initial)}</span>`;
  const href  = '/m.html?slug=' + encodeURIComponent(m.slug || '');
  const bio   = m.bio
    ? `<p class="muted model-bio">${escapeHtml(m.bio)}</p>`
    : '';
  
  const cardClass = 'model-card';

  return `
    <article class="${cardClass}" ${brandStyle(m.brandColor)}>
      <a class="model-card-link" href="${href}" aria-label="View ${escapeHtml(m.name)}">
        ${photo}
        <span class="model-brand-strip" aria-hidden="true"></span>
        <header class="model-head">
          <h3>${escapeHtml(m.name)}</h3>
          ${genderBadge(m.gender, m.accountType)}
        </header>
        ${bio}
      </a>
      ${socialLinks(m.socials)}
    </article>`;
}

function renderEmpty(grid) {
  grid.innerHTML = `
    <div class="models-empty">
      <h3>The roster is filling up</h3>
      <p class="muted">No models yet — model registrations open soon. Check back shortly.</p>
    </div>`;
}

export async function loadModels() {
  const grids = document.querySelectorAll('#modelsGrid');
  if (!grids.length) return;
  for (const grid of grids) {
    grid.innerHTML = '<p class="lb-empty">Loading models…</p>';
  }
  try {
    const { models } = await api.models();
    const list = Array.isArray(models) ? models : [];
    if (!list.length) {
      for (const grid of grids) renderEmpty(grid);
      return;
    }
    const html = list.map(modelCard).join('');
    for (const grid of grids) grid.innerHTML = html;
  } catch (err) {
    for (const grid of grids) {
      grid.innerHTML = `<p class="lb-empty">Could not load models: ${escapeHtml(err.message)}</p>`;
    }
  }
}

export function initModels() {
  // Mount once on DOM ready. Safe to call from any page; if no
  // #modelsGrid is present, this is a no-op.
  if (document.querySelector('#modelsGrid')) {
    loadModels();
  }
}
