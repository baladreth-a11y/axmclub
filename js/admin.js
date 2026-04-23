// Admin panel logic. Self-contained; does not depend on the main
// members-site modules. The only shared piece is styles.css.
//
// Admin key flow:
//   * stored in sessionStorage (tab-scoped, cleared on close)
//   * sent as `x-admin-key` on every request
//   * unlock the panel by pasting the key, pressing Save
//
// All admin endpoints are defined under /api/admin/... in server.ps1's
// Handle-Admin sub-handler and guarded by Require-Admin.

const KEY_SLOT = 'axm.adminKey';
const $ = sel => document.querySelector(sel);

let adminKey = sessionStorage.getItem(KEY_SLOT) || '';

function toast(msg, type = '') {
  const el = $('#toast');
  el.textContent = msg;
  el.className = 'toast ' + type;
  el.classList.remove('hidden');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.add('hidden'), 2600);
}

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

function formatDate(ms) {
  if (!ms) return '—';
  const d = new Date(ms);
  if (isNaN(d.getTime())) return '—';
  return d.toLocaleString(undefined, {
    month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit'
  });
}

async function adminFetch(path, opts = {}) {
  const res = await fetch(path, {
    ...opts,
    headers: {
      ...(opts.headers || {}),
      'x-admin-key': adminKey,
      ...(opts.body ? { 'Content-Type': 'application/json' } : {})
    }
  });
  let data = {};
  try { data = await res.json(); } catch { /* non-JSON */ }
  if (!res.ok) {
    const err = new Error(data.error || `Request failed (${res.status})`);
    err.status = res.status;
    throw err;
  }
  return data;
}

/* ---------- UI visibility ---------------------------------------- */
function setUnlocked(on) {
  $('#passwordsSection').classList.toggle('hidden', !on);
  $('#offersSection').classList.toggle('hidden', !on);
  $('#authNotice').classList.toggle('hidden', on);
}

/* ---------- Passwords ------------------------------------------- */
function passwordRow(p) {
  const redeemers = Array.isArray(p.redeemedBy) ? p.redeemedBy : [];
  const usesDisplay = p.uses > 0 ? p.uses : '<span class="muted">0 (revoked)</span>';
  const redeemed = redeemers.length
    ? escapeHtml(redeemers.join(', '))
    : '<span class="muted">—</span>';
  return `
    <tr>
      <td><code>${escapeHtml(p.code)}</code></td>
      <td>${usesDisplay}</td>
      <td>${redeemed}</td>
      <td class="muted">${escapeHtml(p.note || '')}</td>
      <td class="admin-row-actions">
        <button class="btn btn-outline revoke-btn" data-code="${escapeHtml(p.code)}" ${p.uses === 0 ? 'disabled' : ''}>Revoke</button>
      </td>
    </tr>`;
}

async function loadPasswords() {
  const tbody = $('#passwordsBody');
  tbody.innerHTML = '<tr><td colspan="5" class="admin-empty">Loading…</td></tr>';
  try {
    const { passwords } = await adminFetch('/api/admin/passwords');
    if (!passwords.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="admin-empty">No passwords yet.</td></tr>';
      return;
    }
    tbody.innerHTML = passwords.map(passwordRow).join('');
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="5" class="admin-empty">${escapeHtml(err.message)}</td></tr>`;
  }
}

async function onCreatePassword(e) {
  e.preventDefault();
  const fd = new FormData(e.target);
  const body = {
    password: (fd.get('password') || '').toString().toUpperCase(),
    uses:     parseInt(fd.get('uses'), 10) || 1,
    note:     fd.get('note') || ''
  };
  try {
    const res = await adminFetch('/api/cam/create-password', {
      method: 'POST', body: JSON.stringify(body)
    });
    e.target.reset();
    e.target.querySelector('input[name="uses"]').value = 10;
    toast(`Created ${res.password} (${res.uses} uses).`, 'success');
    loadPasswords();
  } catch (err) {
    toast(err.message, 'error');
  }
}

async function onRevoke(code) {
  if (!confirm(`Revoke ${code}? It will stop granting passes immediately.`)) return;
  try {
    await adminFetch('/api/admin/passwords/revoke', {
      method: 'POST', body: JSON.stringify({ code })
    });
    toast(`${code} revoked.`, 'success');
    loadPasswords();
  } catch (err) {
    toast(err.message, 'error');
  }
}

/* ---------- Offers ---------------------------------------------- */
// Cache of the most recently fetched offers so filter/search can
// re-render locally without another round-trip to the server.
let offersCache = [];

function offerRow(o) {
  const target = o.target && o.target.length ? escapeHtml(o.target) : '<span class="muted">—</span>';
  return `
    <tr>
      <td class="muted">${escapeHtml(formatDate(o.at))}</td>
      <td>
        <strong>${escapeHtml(o.fromName || o.from)}</strong>
        <div class="muted" style="font-size:11px">${escapeHtml(o.from)}</div>
      </td>
      <td>${target}</td>
      <td class="offer-msg" title="${escapeHtml(o.message)}">${escapeHtml(o.message)}</td>
      <td><span class="status-badge ${escapeHtml(o.status)}">${escapeHtml(o.status)}</span></td>
      <td class="admin-row-actions">
        <button class="btn btn-primary accept-btn"  data-from="${escapeHtml(o.from)}" data-id="${escapeHtml(o.id)}" ${o.status === 'accepted' ? 'disabled' : ''}>Accept</button>
        <button class="btn btn-outline decline-btn" data-from="${escapeHtml(o.from)}" data-id="${escapeHtml(o.id)}" ${o.status === 'declined' ? 'disabled' : ''}>Decline</button>
      </td>
    </tr>`;
}

function updateOffersCount(shown, total) {
  const el = $('#offersCount');
  if (!el) return;
  if (!total) { el.textContent = '—'; return; }
  el.textContent = shown === total
    ? `${total} offer${total === 1 ? '' : 's'}`
    : `${shown} / ${total}`;
}

function renderOffers() {
  const tbody = $('#offersBody');
  if (!tbody) return;

  const statusFilter = ($('#offersStatusFilter')?.value || '').toLowerCase();
  const q            = ($('#offersSearch')?.value || '').trim().toLowerCase();

  const filtered = offersCache.filter(o => {
    if (statusFilter && (o.status || '').toLowerCase() !== statusFilter) return false;
    if (!q) return true;
    const hay = [
      o.fromName || '', o.from || '', o.message || '', o.target || ''
    ].join(' \u0001 ').toLowerCase();
    return hay.includes(q);
  });

  if (!offersCache.length) {
    tbody.innerHTML = '<tr><td colspan="6" class="admin-empty">No offers yet.</td></tr>';
  } else if (!filtered.length) {
    tbody.innerHTML = '<tr><td colspan="6" class="admin-empty">No offers match the current filter.</td></tr>';
  } else {
    tbody.innerHTML = filtered.map(offerRow).join('');
  }
  updateOffersCount(filtered.length, offersCache.length);
}

async function loadOffers() {
  const tbody = $('#offersBody');
  tbody.innerHTML = '<tr><td colspan="6" class="admin-empty">Loading…</td></tr>';
  try {
    const { offers } = await adminFetch('/api/admin/offers');
    offersCache = Array.isArray(offers) ? offers : [];
    renderOffers();
  } catch (err) {
    offersCache = [];
    tbody.innerHTML = `<tr><td colspan="6" class="admin-empty">${escapeHtml(err.message)}</td></tr>`;
    updateOffersCount(0, 0);
  }
}

async function setOfferStatus(userEmail, offerId, status) {
  try {
    await adminFetch('/api/admin/offers/status', {
      method: 'POST',
      body: JSON.stringify({ userEmail, offerId, status })
    });
    toast(`Offer ${status}.`, 'success');
    loadOffers();
  } catch (err) {
    toast(err.message, 'error');
  }
}

/* ---------- Key management -------------------------------------- */
function applyKey(next) {
  adminKey = (next || '').trim();
  if (adminKey) {
    sessionStorage.setItem(KEY_SLOT, adminKey);
  } else {
    sessionStorage.removeItem(KEY_SLOT);
  }
  setUnlocked(!!adminKey);
  if (adminKey) {
    loadPasswords();
    loadOffers();
  }
}

/* ---------- Init ------------------------------------------------ */
$('#adminKeyInput').value = adminKey;
setUnlocked(!!adminKey);
if (adminKey) {
  loadPasswords();
  loadOffers();
}

$('#saveKeyBtn').addEventListener('click', () => applyKey($('#adminKeyInput').value));
$('#clearKeyBtn').addEventListener('click', () => {
  $('#adminKeyInput').value = '';
  applyKey('');
  toast('Admin key cleared.');
});
$('#adminKeyInput').addEventListener('keydown', e => {
  if (e.key === 'Enter') { e.preventDefault(); applyKey(e.target.value); }
});

$('#newPasswordForm').addEventListener('submit', onCreatePassword);

// Delegated handlers for row buttons.
$('#passwordsBody').addEventListener('click', e => {
  const btn = e.target.closest('.revoke-btn');
  if (btn && !btn.disabled) onRevoke(btn.dataset.code);
});
$('#offersBody').addEventListener('click', e => {
  const accept = e.target.closest('.accept-btn');
  if (accept && !accept.disabled) {
    setOfferStatus(accept.dataset.from, accept.dataset.id, 'accepted');
    return;
  }
  const decline = e.target.closest('.decline-btn');
  if (decline && !decline.disabled) {
    setOfferStatus(decline.dataset.from, decline.dataset.id, 'declined');
  }
});

// Filter / search toolbar — re-render from the local cache so
// typing feels instant and doesn't hammer the API.
$('#offersStatusFilter')?.addEventListener('change', renderOffers);
$('#offersSearch')?.addEventListener('input', renderOffers);
