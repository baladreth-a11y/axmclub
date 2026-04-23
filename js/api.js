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

export const api = {
  me:           () => request('/api/me'),
  stats:        () => request('/api/stats'),
  leaderboard:  () => request('/api/leaderboard'),
  register:     body => request('/api/register', { method: 'POST', body }),
  login:        body => request('/api/login',    { method: 'POST', body }),
  logout:       () => request('/api/logout',     { method: 'POST' }),
  spin:         () => request('/api/spin',       { method: 'POST' }),
  rewards:      () => request('/api/rewards'),
  redeem:       rewardId => request('/api/redeem', { method: 'POST', body: { rewardId } }),
  redemptions:  () => request('/api/redemptions'),
  history:      () => request('/api/history'),

  camStatus:         () => request('/api/cam/status'),
  camRedeemPassword: password => request('/api/cam/redeem-password', { method: 'POST', body: { password } }),

  tasks:             () => request('/api/tasks'),
  claimTask:         taskId => request('/api/tasks/claim', { method: 'POST', body: { taskId } }),

  buyTokens:         amount => request('/api/tokens/buy', { method: 'POST', body: { amount } }),
  makeOffer:         body   => request('/api/offer',      { method: 'POST', body })
};
