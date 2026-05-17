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

function logSessionAction(msg) {
  const container = $('#sessionActionLog');
  if (!container) return;
  const emptyEl = container.querySelector('.action-log-empty');
  if (emptyEl) emptyEl.remove();
  
  const time = new Date().toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  const entry = document.createElement('div');
  entry.className = 'action-log-entry';
  entry.innerHTML = `<span class="action-time">[${time}]</span><span class="action-msg">${escapeHtml(msg)}</span>`;
  container.prepend(entry);
  
  const countEl = $('#actionLogCount');
  if (countEl) {
    const current = container.querySelectorAll('.action-log-entry').length;
    countEl.textContent = current;
  }
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

function reportError(err) {
  console.error(err);
  toast(err.message || String(err), 'error');
}

/* ---------- UI visibility & Navigation -------------------------- */
let activeTab = 'dashboard';

function switchTab(tabId) {
  activeTab = tabId;
  
  // Highlight active tab button
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tabId);
  });
  
  // Hide all sections except the active tab's section
  const cards = [
    { id: 'dashboardSection', tab: 'dashboard' },
    { id: 'usersSection', tab: 'users' },
    { id: 'passwordsSection', tab: 'passwords' },
    { id: 'feedbackSection', tab: 'feedback' },
    { id: 'offersSection', tab: 'offers' },
    { id: 'chatSection', tab: 'chat' },
    { id: 'configSection', tab: 'config' },
    { id: 'dbSection', tab: 'system' },
    { id: 'logsSection', tab: 'system' }
  ];
  
  const unlocked = !!adminKey;
  cards.forEach(c => {
    const el = $('#' + c.id);
    if (el) {
      el.classList.toggle('hidden', !unlocked || c.tab !== tabId);
    }
  });
  
  // Trigger fetch for the active tab only
  if (unlocked) {
    if (tabId === 'dashboard') loadDashboardStats();
    else if (tabId === 'users') loadUsers();
    else if (tabId === 'passwords') loadPasswords();
    else if (tabId === 'feedback') loadFeedback();
    else if (tabId === 'offers') loadOffers();
    else if (tabId === 'chat') loadChat();
    else if (tabId === 'config') loadConfig();
    else if (tabId === 'system') { loadDb(); loadLogs(); }
  }
}

function setUnlocked(on) {
  $('#adminTabsNav').classList.toggle('hidden', !on);
  $('#authNotice').classList.toggle('hidden', on);
  $('#cornerStatsWidget')?.classList.toggle('hidden', !on);
  if (on) {
    switchTab(activeTab);
    if (!setUnlocked._interval) {
      setUnlocked._interval = setInterval(() => {
        if (adminKey) {
          loadDashboardStats();
        }
      }, 10000);
    }
  } else {
    const sections = [
      'dashboardSection', 'usersSection', 'passwordsSection', 'feedbackSection',
      'offersSection', 'chatSection', 'configSection', 'dbSection', 'logsSection'
    ];
    sections.forEach(s => $('#' + s)?.classList.add('hidden'));
    if (setUnlocked._interval) {
      clearInterval(setUnlocked._interval);
      setUnlocked._interval = null;
    }
  }
}

async function loadDashboardStats() {
  try {
    const data = await adminFetch('/api/admin/db');
    if (!data || !data.db) return;
    const db = data.db;
    const users = db.users || {};

    // Visits
    const visits = db.stats?.visits || 0;
    if ($('#statVisits'))  $('#statVisits').textContent  = Number(visits).toLocaleString();
    if ($('#cornerStatVisits')) $('#cornerStatVisits').textContent = Number(visits).toLocaleString();

    // Spins
    const spins = db.stats?.spins || 0;
    if ($('#statSpins'))   $('#statSpins').textContent   = Number(spins).toLocaleString();

    // Members & Models
    const userKeys     = Object.keys(users);
    const totalUsers   = userKeys.length;
    const totalModels  = userKeys.filter(e => (users[e].accountType || '') === 'model').length;
    if ($('#statMembers')) $('#statMembers').textContent = totalUsers.toLocaleString();
    if ($('#statModels'))  $('#statModels').textContent  = totalModels.toLocaleString();

    // Pending offers
    const offers        = Array.isArray(db.offers) ? db.offers : [];
    const pendingOffers = offers.filter(o => o.status === 'pending').length;
    if ($('#statOffers'))  $('#statOffers').textContent  = pendingOffers.toLocaleString();

    // Open feedback
    const feedback     = Array.isArray(db.feedback) ? db.feedback : [];
    const openFeedback = feedback.filter(f => (f.status || 'open') === 'open').length;
    if ($('#statFeedback')) $('#statFeedback').textContent = openFeedback.toLocaleString();

    // Online now (seen in last 60 s)
    const now = Date.now();
    let onlineCount = 0;
    userKeys.forEach(email => {
      const u = users[email];
      if (u.lastSeenMs && (now - u.lastSeenMs) <= 60000) onlineCount++;
    });
    if ($('#statOnline'))      $('#statOnline').textContent      = onlineCount.toLocaleString();
    if ($('#cornerStatOnline')) $('#cornerStatOnline').textContent = onlineCount.toLocaleString();

  } catch (err) {
    console.error('Failed to load stats:', err);
  }
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
    logSessionAction(`Created password code "${res.password}" with ${res.uses} uses`);
    loadPasswords();
  } catch (err) {
    reportError(err);
  }
}

async function onRevoke(code) {
  if (!confirm(`Revoke ${code}? It will stop granting passes immediately.`)) return;
  try {
    await adminFetch('/api/admin/passwords/revoke', {
      method: 'POST', body: JSON.stringify({ code })
    });
    toast(`${code} revoked.`, 'success');
    logSessionAction(`Revoked password code "${code}"`);
    loadPasswords();
  } catch (err) {
    reportError(err);
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
    logSessionAction(`Marked offer from ${userEmail} as ${status}`);
    loadOffers();
  } catch (err) {
    reportError(err);
  }
}

/* ---- Feedback inbox -------------------------------------------- */
let feedbackCache = [];

function feedbackRow(f) {
  const type = (f.type || 'other').toLowerCase();
  const status = (f.status || 'open').toLowerCase();
  const cls = status === 'resolved' ? ' is-resolved' : (status === 'archived' ? ' is-archived' : '');
  const meta = [
    f.page ? ('on ' + f.page) : '',
    f.userEmail ? ('by ' + f.userEmail) : 'anonymous',
    f.contact ? ('reply: ' + f.contact) : '',
    formatDate(f.at)
  ].filter(Boolean).join(' · ');
  const actions = status === 'open'
    ? `<div class="admin-row-actions">
         <button class="btn btn-outline fb-resolve-btn" data-id="${escapeHtml(f.id)}" data-status="resolved">Resolve</button>
         <button class="btn btn-ghost fb-resolve-btn" data-id="${escapeHtml(f.id)}" data-status="archived">Archive</button>
       </div>`
    : `<div class="admin-row-actions">
         <button class="btn btn-ghost fb-resolve-btn" data-id="${escapeHtml(f.id)}" data-status="open">Reopen</button>
       </div>`;
  return `
    <div class="feedback-row${cls}">
      <div>
        <span class="feedback-pill ${escapeHtml(type)}">${escapeHtml(type)}</span>
        <div class="fb-meta" style="margin-top:6px">${escapeHtml(status)}</div>
      </div>
      <div>
        <div class="fb-msg">${escapeHtml(f.message)}</div>
        <div class="fb-meta">${escapeHtml(meta)}</div>
      </div>
      ${actions}
    </div>`;
}

function renderFeedback() {
  const body = $('#feedbackBody');
  if (!body) return;
  const typeF = ($('#feedbackTypeFilter')?.value || '').toLowerCase();
  const statusF = ($('#feedbackStatusFilter')?.value || '').toLowerCase();
  const filtered = feedbackCache.filter(f => {
    if (typeF && (f.type || '').toLowerCase() !== typeF) return false;
    if (statusF && (f.status || 'open').toLowerCase() !== statusF) return false;
    return true;
  });
  if (!feedbackCache.length) {
    body.innerHTML = '<div class="admin-empty">No feedback yet.</div>';
  } else if (!filtered.length) {
    body.innerHTML = '<div class="admin-empty">No feedback matches the current filter.</div>';
  } else {
    body.innerHTML = filtered.map(feedbackRow).join('');
  }
  const el = $('#feedbackCount');
  if (el) {
    if (!feedbackCache.length) { el.textContent = '—'; }
    else if (filtered.length === feedbackCache.length) { el.textContent = `${feedbackCache.length} item${feedbackCache.length === 1 ? '' : 's'}`; }
    else { el.textContent = `${filtered.length} / ${feedbackCache.length}`; }
  }
}

async function loadFeedback() {
  const body = $('#feedbackBody');
  if (!body) return;
  body.innerHTML = '<div class="admin-empty">Loading…</div>';
  try {
    const { feedback } = await adminFetch('/api/admin/feedback');
    feedbackCache = Array.isArray(feedback) ? feedback : [];
    renderFeedback();
  } catch (err) {
    feedbackCache = [];
    body.innerHTML = `<div class="admin-empty">${escapeHtml(err.message)}</div>`;
  }
}

async function setFeedbackStatus(id, status) {
  try {
    await adminFetch('/api/admin/feedback/resolve', {
      method: 'POST',
      body: JSON.stringify({ id, status })
    });
    toast(`Feedback ${status}.`, 'success');
    logSessionAction(`Marked feedback item ${id.slice(0, 8)}... as ${status}`);
    loadFeedback();
  } catch (err) {
    reportError(err);
  }
}

/* ---------- DB Viewer ------------------------------------------- */
async function loadDb() {
  const viewer = $('#dbViewer');
  const countEl = $('#dbCount');
  viewer.textContent = 'Loading…';
  countEl.textContent = '—';
  try {
    const data = await adminFetch('/api/admin/db');
    const jsonStr = JSON.stringify(data, null, 2);
    viewer.textContent = jsonStr;
    countEl.textContent = `${Object.keys(data).length} keys`;
  } catch (err) {
    viewer.textContent = `Error: ${err.message}`;
    countEl.textContent = '—';
  }
}

/* ---------- Logs Viewer ----------------------------------------- */
async function loadLogs() {
  const viewer = $('#logsViewer');
  const countEl = $('#logsCount');
  viewer.textContent = 'Loading…';
  countEl.textContent = '—';
  try {
    const data = await adminFetch('/api/admin/logs');
    const logsStr = Array.isArray(data.logs) ? data.logs.join('\n') : 'No logs available';
    viewer.textContent = logsStr;
    const lines = logsStr.split('\n').length;
    countEl.textContent = `${lines} line${lines === 1 ? '' : 's'}`;
  } catch (err) {
    viewer.textContent = `Error: ${err.message}`;
    countEl.textContent = '—';
  }
}

/* ---- Users ----------------------------------------------------- */
// Local cache + edit-modal state. The list endpoint returns a snapshot;
// every adjust/delete just re-fetches.
let usersCache = [];
let editingEmail = null;

function tierClass(tier) {
  return ({ Silver: 'silver', Gold: 'gold', Platinum: 'platinum' }[tier] || 'silver');
}

function userRow(u) {
  const verifyBtn = !u.emailVerified
    ? `<button class="btn btn-primary quick-verify-btn" data-email="${escapeHtml(u.email)}" style="background:#28a745; border-color:#28a745; padding: 4px 8px; font-size: 11px; font-weight:600; text-transform:uppercase; letter-spacing:0.05em;">✓ Verify</button>`
    : '';
  return `
    <tr>
      <td class="muted" style="white-space:nowrap">${escapeHtml(formatDate(u.joined))}</td>
      <td class="user-id">
        <strong>${escapeHtml(u.name || '—')}</strong>
        <small>${escapeHtml(u.email)}</small>
      </td>
      <td><span class="acct-pill ${escapeHtml(u.accountType)}">${escapeHtml(u.accountType)}</span></td>
      <td><span class="tier-badge ${tierClass(u.tier)}">${escapeHtml(u.tier)}</span></td>
      <td>
        <div style="display:flex; align-items:center; gap:6px;">
          <span>${u.points.toLocaleString()}</span>
          <button class="btn btn-outline btn-xs quick-boost-points" data-email="${escapeHtml(u.email)}" style="padding:2px 6px; font-size:10px;">+500</button>
        </div>
      </td>
      <td>
        <div style="display:flex; align-items:center; gap:6px;">
          <span>${u.tokens.toLocaleString()}</span>
          <button class="btn btn-outline btn-xs quick-boost-tokens" data-email="${escapeHtml(u.email)}" style="padding:2px 6px; font-size:10px;">+50</button>
        </div>
      </td>
      <td class="muted">${u.streak ? '🔥 ' + u.streak : '—'}</td>
      <td class="admin-row-actions">
        ${verifyBtn}
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
  f.elements['emailVerified'].checked = !!u.emailVerified;
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
    email:         editingEmail,
    name:          (fd.get('name') || '').toString().trim(),
    points:        parseInt(fd.get('points'), 10) || 0,
    tokens:        parseInt(fd.get('tokens'), 10) || 0,
    accountType:   fd.get('accountType'),
    rank:          (fd.get('rank') || '').toString().trim(),
    emailVerified: e.target.querySelector('input[name="emailVerified"]').checked
  };
  try {
    await adminFetch('/api/admin/users/adjust', {
      method: 'POST',
      body: JSON.stringify(body)
    });
    toast('User updated.', 'success');
    logSessionAction(`Updated user account fields for ${editingEmail}`);
    closeUserEdit();
    loadUsers();
  } catch (err) {
    reportError(err);
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
    logSessionAction(`Deleted user account for ${email} (${displayName})`);
    loadUsers();
  } catch (err) {
    reportError(err);
  }
}

async function onUserQuickVerify(email) {
  const u = usersCache.find(x => x.email === email);
  if (!u) return;
  
  const body = {
    email:         u.email,
    name:          u.name || '',
    points:        u.points || 0,
    tokens:        u.tokens || 0,
    accountType:   u.accountType || 'supporter',
    rank:          u.rank || '',
    emailVerified: true
  };
  
  try {
    await adminFetch('/api/admin/users/adjust', {
      method: 'POST',
      body: JSON.stringify(body)
    });
    toast(`Successfully verified ${email}!`, 'success');
    logSessionAction(`Verified email address for ${email}`);
    loadUsers();
  } catch (err) {
    reportError(err);
  }
}

async function onUserQuickBoost(email, type, amount) {
  const u = usersCache.find(x => x.email === email);
  if (!u) return;
  
  const newPoints = type === 'points' ? (u.points + amount) : u.points;
  const newTokens = type === 'tokens' ? (u.tokens + amount) : u.tokens;
  
  const body = {
    email:         u.email,
    name:          u.name || '',
    points:        newPoints,
    tokens:        newTokens,
    accountType:   u.accountType || 'supporter',
    rank:          u.rank || '',
    emailVerified: !!u.emailVerified
  };
  
  try {
    await adminFetch('/api/admin/users/adjust', {
      method: 'POST',
      body: JSON.stringify(body)
    });
    toast(`Boosted ${amount} ${type} to ${email}!`, 'success');
    logSessionAction(`Boosted ${amount} ${type} for ${email} (New: ${type === 'points' ? newPoints : newTokens})`);
    loadUsers();
  } catch (err) {
    reportError(err);
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
}

/* ---------- Init ------------------------------------------------ */
$('#adminKeyInput').value = adminKey;
setUnlocked(!!adminKey);

/* ---------- Chat Moderation ------------------------------------- */
async function loadChat() {
  const body = $('#chatBody');
  if (!body) return;
  body.innerHTML = '<div class="admin-empty">Loading messages…</div>';
  try {
    const { messages } = await adminFetch('/api/chat/public/messages');
    if (!messages.length) {
      body.innerHTML = '<div class="admin-empty">No messages in history.</div>';
      return;
    }
    body.innerHTML = messages.reverse().map(m => `
      <div class="feedback-row" style="padding: 10px; border-bottom: 1px solid var(--line); display: flex; justify-content: space-between; align-items: center;">
        <div style="flex: 1;">
          <div style="font-weight: 600; font-size: 13px;">${escapeHtml(m.name)} <span class="muted" style="font-weight: 400; font-size: 11px;">· ${escapeHtml(formatDate(m.at))}</span></div>
          <div style="font-size: 14px; margin-top: 4px;">${escapeHtml(m.text)}</div>
        </div>
        <button class="btn btn-ghost chat-delete-btn" data-id="${escapeHtml(m.id)}" style="color: var(--danger);">Delete</button>
      </div>
    `).join('');
  } catch (err) {
    body.innerHTML = `<div class="admin-empty" style="color: var(--danger);">${escapeHtml(err.message)}</div>`;
  }
}

$('#chatRefreshBtn')?.addEventListener('click', loadChat);
$('#chatBody')?.addEventListener('click', async e => {
  const btn = e.target.closest('.chat-delete-btn');
  if (!btn) return;
  const id = btn.dataset.id;
  if (!confirm('Delete this message?')) return;
  
  try {
    await adminFetch('/api/admin/chat/delete', {
      method: 'POST',
      body: JSON.stringify({ id })
    });
    toast('Message deleted.', 'success');
    loadChat();
  } catch (err) {
    reportError(err);
  }
});

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

// Feedback inbox: filter + resolve/reopen buttons.
$('#feedbackTypeFilter')?.addEventListener('change', renderFeedback);
$('#feedbackStatusFilter')?.addEventListener('change', renderFeedback);
$('#feedbackBody')?.addEventListener('click', e => {
  const btn = e.target.closest('.fb-resolve-btn');
  if (!btn) return;
  setFeedbackStatus(btn.dataset.id, btn.dataset.status || 'resolved');
});

// Users tab: filter, edit, delete.
$('#usersTypeFilter')?.addEventListener('change', renderUsers);
$('#usersTierFilter')?.addEventListener('change', renderUsers);
$('#usersSearch')?.addEventListener('input', renderUsers);

$('#usersBody').addEventListener('click', e => {
  const verifyBtn = e.target.closest('.quick-verify-btn');
  if (verifyBtn) { onUserQuickVerify(verifyBtn.dataset.email); return; }
  
  const boostPointsBtn = e.target.closest('.quick-boost-points');
  if (boostPointsBtn) { onUserQuickBoost(boostPointsBtn.dataset.email, 'points', 500); return; }
  
  const boostTokensBtn = e.target.closest('.quick-boost-tokens');
  if (boostTokensBtn) { onUserQuickBoost(boostTokensBtn.dataset.email, 'tokens', 50); return; }

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

// DB and Logs refresh buttons
$('#dbRefreshBtn')?.addEventListener('click', loadDb);
$('#logsRefreshBtn')?.addEventListener('click', loadLogs);

/* ---------- Config ---------------------------------------------- */
async function loadConfig() {
  const wheelEl = $('#configWheel');
  const catalogEl = $('#configCatalog');
  const tasksEl = $('#configTasks');
  if (!wheelEl || !catalogEl || !tasksEl) return;
  
  try {
    const data = await adminFetch('/api/admin/config');
    wheelEl.value = JSON.stringify(data.wheelVariants, null, 2);
    catalogEl.value = JSON.stringify(data.catalog, null, 2);
    tasksEl.value = JSON.stringify(data.tasks, null, 2);
  } catch (err) {
    reportError(err);
  }
}

$('#configForm')?.addEventListener('submit', async e => {
  e.preventDefault();
  const submitBtn = e.target.querySelector('button[type="submit"]');
  const originalText = submitBtn ? submitBtn.textContent : null;
  if (submitBtn) { submitBtn.disabled = true; submitBtn.textContent = 'Saving…'; }
  
  try {
    const wheelVariants = JSON.parse($('#configWheel').value);
    const catalog = JSON.parse($('#configCatalog').value);
    const tasks = JSON.parse($('#configTasks').value);
    
    await adminFetch('/api/admin/config', {
      method: 'POST',
      body: JSON.stringify({ wheelVariants, catalog, tasks })
    });
    toast('Configuration saved successfully.', 'success');
    logSessionAction('Saved updated Site Configuration JSON');
    loadConfig();
  } catch (err) {
    reportError(err);
    toast('Failed to save config. Make sure JSON is valid.', 'error');
  } finally {
    if (submitBtn) { submitBtn.disabled = false; submitBtn.textContent = originalText; }
  }
});

// Tab Switching
$('#adminTabsNav')?.addEventListener('click', e => {
  const btn = e.target.closest('.tab-btn');
  if (btn) switchTab(btn.dataset.tab);
});

// Dashboard Actions
$('#sendSummaryBtn')?.addEventListener('click', async e => {
  e.target.disabled = true;
  const originalText = e.target.textContent;
  e.target.textContent = 'Sending report…';
  try {
    const res = await adminFetch('/api/admin/reports/summary', { method: 'POST' });
    toast(`Email successfully dispatched to ${res.recipient}!`, 'success');
  } catch (err) {
    toast(`Failed to send report: ${err.message}`, 'error');
  } finally {
    e.target.disabled = false;
    e.target.textContent = originalText;
  }
});

$('#refreshStatsBtn')?.addEventListener('click', async e => {
  e.target.disabled = true;
  await loadDashboardStats();
  toast('Live stats updated.', 'success');
  e.target.disabled = false;
});

// Quick Points / Tokens Adjustments
$('#quickAddPoints100')?.addEventListener('click', () => {
  const el = $('#userEditForm').elements['points'];
  el.value = (parseInt(el.value, 10) || 0) + 100;
});
$('#quickAddPoints1000')?.addEventListener('click', () => {
  const el = $('#userEditForm').elements['points'];
  el.value = (parseInt(el.value, 10) || 0) + 1000;
});
$('#quickAddTokens10')?.addEventListener('click', () => {
  const el = $('#userEditForm').elements['tokens'];
  el.value = (parseInt(el.value, 10) || 0) + 10;
});
$('#quickAddTokens50')?.addEventListener('click', () => {
  const el = $('#userEditForm').elements['tokens'];
  el.value = (parseInt(el.value, 10) || 0) + 50;
});
