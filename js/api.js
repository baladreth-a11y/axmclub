// Single fetch helper. Adds one named method per backend endpoint.
// Add new features by adding new methods here only.
async function request(path, { method = 'GET', body } = {}) {
  const res = await fetch(path, {
    method,
    credentials: 'include',
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined
  });

  let data = {};
  try { data = await res.json(); } catch { /* non-JSON response */ }

  if (!res.ok) {
    const err = new Error(data.error || `Request failed (${res.status})`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

// Upload helper: POST a single file under field name `photo` as
// multipart/form-data. Do NOT set Content-Type ourselves — the browser
// fills in the boundary automatically when given a FormData body.
async function uploadFile(path, file, fieldName = 'photo') {
  const fd = new FormData();
  fd.append(fieldName, file, file.name);
  const res = await fetch(path, {
    method: 'POST',
    credentials: 'include',
    body: fd
  });

  let data = {};
  try { data = await res.json(); } catch { /* non-JSON response */ }

  if (!res.ok) {
    const err = new Error(data.error || `Upload failed (${res.status})`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}
export const api = {
  me:           () => request('/api/me'),
  stats:        () => request('/api/stats'),
  leaderboard:  () => request('/api/leaderboard'),
  register:     body => request('/api/register', { method: 'POST', body }),
  login:        body => request('/api/login',    { method: 'POST', body }),
  logout:       () => request('/api/logout',     { method: 'POST' }),
  authResetRequest:  email => request('/api/auth/reset-request', { method: 'POST', body: { email } }),
  authResetPassword: body  => request('/api/auth/reset-password', { method: 'POST', body }),
  spin:         () => request('/api/spin',       { method: 'POST' }),
  rewards:      () => request('/api/rewards'),
  redeem:       rewardId => request('/api/redeem', { method: 'POST', body: { rewardId } }),
  redemptions:  () => request('/api/redemptions'),
  history:      () => request('/api/history'),

  camStatus:         () => request('/api/cam/status'),
  camRedeemPassword: password => request('/api/cam/redeem-password', { method: 'POST', body: { password } }),

  // Cam2cam signalling. All require auth; both peers must have cam2cam=true.
  setCam2cam:    enabled => request('/api/cam2cam',     { method: 'POST', body: { enabled: !!enabled } }),
  camRequest:    to       => request('/api/cam/request', { method: 'POST', body: { to } }),
  camInbox:      (since = 0) => request('/api/cam/inbox?since=' + (since | 0)),
  camRespond:    (id, accept) => request('/api/cam/respond', { method: 'POST', body: { id, accept: !!accept } }),
  camSignal:     (id, kind, payload) => request('/api/cam/signal', { method: 'POST', body: { id, kind, payload } }),
  camSignalGet:  (id, since = 0) => request('/api/cam/signal?id=' + encodeURIComponent(id) + '&since=' + (since | 0)),
  camEnd:        id => request('/api/cam/end', { method: 'POST', body: { id } }),

  tasks:             () => request('/api/tasks'),
  claimTask:         taskId => request('/api/tasks/claim', { method: 'POST', body: { taskId } }),

  buyTokens:         amount => request('/api/tokens/buy', { method: 'POST', body: { amount } }),
  makeOffer:         body   => request('/api/offer',      { method: 'POST', body }),
  // Public model gallery (no auth) + per-slug detail (verified-only).
  models:       () => request('/api/models'),
  modelBySlug:  slug => request('/api/models/' + encodeURIComponent(slug)),

  // Email verification.
  verifyStart: () => request('/api/verify/start', { method: 'POST' }),

  // Model dashboard. Each requires the caller to be signed in with
  // accountType == 'model' (server enforces with Require-Model).
  modelProfile:        () => request('/api/model/profile'),
  modelUpdateProfile:  body => request('/api/model/profile',  { method: 'POST', body }),
  modelPasswords:      () => request('/api/model/passwords'),
  modelCreatePassword: body => request('/api/model/passwords', { method: 'POST', body }),
  modelRevokePassword: code => request('/api/model/passwords/revoke', { method: 'POST', body: { code } }),
  modelOffers:         () => request('/api/model/offers'),
  modelRespondOffer:   body => request('/api/model/offers/respond', { method: 'POST', body }),
  modelStats:          () => request('/api/model/stats'),

  // Photo + gallery uploads (multipart). Files arrive under field 'photo'.
  uploadModelPhoto: file => uploadFile('/api/model/photo', file),
  galleryAdd:       file => uploadFile('/api/model/gallery/add', file),
  galleryRemove:    url  => request('/api/model/gallery/remove', { method: 'POST', body: { url } }),

  // Feedback widget. POST is anonymous-friendly.
  submitFeedback:        body => request('/api/feedback', { method: 'POST', body }),

  // Communicator: presence + 1:1 chat. All require auth.
  online:        () => request('/api/online'),
  chatThreads:   () => request('/api/chat/threads'),
  chatMessages:  (peer, since = 0) =>
    request('/api/chat/messages?peer=' + encodeURIComponent(peer) + '&since=' + (since | 0)),
  chatSend:      (peer, text) => request('/api/chat/send', { method: 'POST', body: { peer, text } }),
  chatPublicMessages: since => request('/api/chat/public/messages?since=' + (since | 0)),
  chatPublicSend:     text => request('/api/chat/public/send', { method: 'POST', body: { text } }),
  chatPolicy:    policy => request('/api/chat/policy', { method: 'POST', body: { policy } })
};
