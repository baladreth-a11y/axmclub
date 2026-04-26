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
  $('#usersSection').classList.toggle('hidden', !on);
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

/* ---------- Users ----------------------------------------------- */
// Local cache + edit-modal state. The list endpoint returns a snapshot;
// every adjust/delete just re-fetches.
let usersCache = [];
let editingEmail = null;

function tierClass(tier) {
  return ({ Silver: 'silver', Gold: 'gold', Platinum: 'platinum' }[tier] || 'silver');
}

function userRow(u) {
  return `
    <tr>
      <td class="muted" style="white-space:nowrap">${escapeHtml(formatDate(u.joined))}</td>
      <td class="user-id">
        <strong>${escapeHtml(u.name || '—')}</strong>
        <small>${escapeHtml(u.email)}</small>
      </td>
      <td><span class="acct-pill ${escapeHtml(u.accountType)}">${escapeHtml(u.accountType)}</span></td>
      <td><span class="tier-badge ${tierClass(u.tier)}">${escapeHtml(u.tier)}</span></td>
      <td>${u.points.toLocaleString()}</td>
      <td>${u.tokens.toLocaleString()}</td>
      <td class="muted">${u.streak ? '🔥 ' + u.streak : '—'}</td>
      <td class="admin-row-actions">
        <button class="btn btn-outline edit-user-btn" data-email="${escapeHtml(u.email)}">Edit</button>
        <button class="btn btn-outline delete-user-btn" data-email="${escapeHtml(u.email)}" data-name="${escapeHtml(u.name || u.email)}">Delete</button>
      </td>
    </tr>`;
}

function updateUsersCount(shown, total) {
  const el = $('#usersCount');
  if (!el) return;
  if (!total) { el.textContent = '—'; return; }
  el.textContent = shown === total
    ? `${total} user${total === 1 ? '' : 's'}`
    : `${shown} / ${total}`;
}

function renderUsers() {
  const tbody = $('#usersBody');
  if (!tbody) return;
  const typeF = ($('#usersTypeFilter')?.value || '').toLowerCase();
  const tierF = ($('#usersTierFilter')?.value || '');
  const q     = ($('#usersSearch')?.value || '').trim().toLowerCase();

  const filtered = usersCache.filter(u => {
    if (typeF && (u.accountType || '').toLowerCase() !== typeF) return false;
    if (tierF && u.tier !== tierF) return false;
    if (!q) return true;
    const hay = ((u.name || '') + ' \u0001 ' + (u.email || '')).toLowerCase();
    return hay.includes(q);
  });

  if (!usersCache.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="admin-empty">No users yet.</td></tr>';
  } else if (!filtered.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="admin-empty">No users match the current filter.</td></tr>';
  } else {
    tbody.innerHTML = filtered.map(userRow).join('');
  }
  updateUsersCount(filtered.length, usersCache.length);
}

async function loadUsers() {
  const tbody = $('#usersBody');
  tbody.innerHTML = '<tr><td colspan="8" class="admin-empty">Loading…</td></tr>';
  try {
    const { users } = await adminFetch('/api/admin/users');
    usersCache = Array.isArray(users) ? users : [];
    renderUsers();
  } catch (err) {
    usersCache = [];
    tbody.innerHTML = `<tr><td colspan="8" class="admin-empty">${escapeHtml(err.message)}</td></tr>`;
    updateUsersCount(0, 0);
  }
}

function openUserEdit(email) {
  const u = usersCache.find(x => x.email === email);
  if (!u) return;
  editingEmail = email;
  $('#userEditEmail').textContent = email;
  const f = $('#userEditForm');
  f.elements['name'].value        = u.name || '';
  f.elements['points'].value      = u.points;
  f.elements['tokens'].value      = u.tokens;
  f.elements['accountType'].value = u.accountType;
  f.elements['rank'].value        = u.rank || '';
  $('#userEditBackdrop').classList.remove('hidden');
  // Focus the points field by default (most-edited).
  requestAnimationFrame(() => f.elements['points']?.focus());
}

function closeUserEdit() {
  editingEmail = null;
  $('#userEditBackdrop').classList.add('hidden');
}

async function onUserEditSubmit(e) {
  e.preventDefault();
  if (!editingEmail) return;
  const fd = new FormData(e.target);
  const body = {
    email:       editingEmail,
    name:        (fd.get('name') || '').toString().trim(),
    points:      parseInt(fd.get('points'), 10) || 0,
    tokens:      parseInt(fd.get('tokens'), 10) || 0,
    accountType: fd.get('accountType'),
    rank:        (fd.get('rank') || '').toString().trim()
  };
  try {
    await adminFetch('/api/admin/users/adjust', {
      method: 'POST',
      body: JSON.stringify(body)
    });
    toast('User updated.', 'success');
    closeUserEdit();
    loadUsers();
  } catch (err) {
    toast(err.message, 'error');
  }
}

async function onUserDelete(email, displayName) {
  // Two-prompt confirmation: irreversible action.
  if (!confirm(`Delete account for ${displayName} (${email})?\nThis cannot be undone.`)) return;
  const typed = prompt(`To confirm, type the email exactly:\n${email}`);
  if ((typed || '').trim().toLowerCase() !== email.toLowerCase()) {
    toast('Email did not match. Cancelled.', 'error');
    return;
  }
  try {
    await adminFetch('/api/admin/users/delete', {
      method: 'POST',
      body: JSON.stringify({ email })
    });
    toast(`Deleted ${email}.`, 'success');
    loadUsers();
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
    loadUsers();
    loadPasswords();
    loadOffers();
  }
}

/* ---------- Init ------------------------------------------------ */
$('#adminKeyInput').value = adminKey;
setUnlocked(!!adminKey);
if (adminKey) {
  loadUsers();
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

// Users tab: filter, edit, delete.
$('#usersTypeFilter')?.addEventListener('change', renderUsers);
$('#usersTierFilter')?.addEventListener('change', renderUsers);
$('#usersSearch')?.addEventListener('input', renderUsers);

$('#usersBody').addEventListener('click', e => {
  const editBtn = e.target.closest('.edit-user-btn');
  if (editBtn) { openUserEdit(editBtn.dataset.email); return; }
  const delBtn = e.target.closest('.delete-user-btn');
  if (delBtn)  { onUserDelete(delBtn.dataset.email, delBtn.dataset.name); }
});

$('#userEditClose').addEventListener('click', closeUserEdit);
$('#userEditBackdrop').addEventListener('click', e => {
  if (e.target.id === 'userEditBackdrop') closeUserEdit();
});
$('#userEditForm').addEventListener('submit', onUserEditSubmit);
document.addEventListener('keydown', e => {
  if (e.key === 'Escape' && !$('#userEditBackdrop').classList.contains('hidden')) {
    closeUserEdit();
  }
});
