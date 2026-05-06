// Dom + small pure helpers.
export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

export function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

export function tierFor(points) {
  if (points >= 1500) return 'Platinum';
  if (points >= 500)  return 'Gold';
  return 'Silver';
}

export function nextTierInfo(points) {
  if (points >= 1500) return { next: 'Max tier', start: 1500, target: points, done: true };
  if (points >= 500)  return { next: 'Platinum', start: 500, target: 1500 };
  return { next: 'Gold', start: 0, target: 500 };
}

export function formatDate(ms) {
  if (!ms) return '—';
  const d = new Date(ms);
  if (isNaN(d.getTime())) return '—';
  return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

export function formatRelative(ms) {
  if (!ms) return 'Never';
  const diff = Date.now() - ms;
  if (diff < 60_000) return 'Just now';
  const mins = Math.floor(diff / 60_000);
  if (mins < 60) return mins + 'm ago';
  const hours = Math.floor(mins / 60);
  if (hours < 24) return hours + 'h ago';
  const days = Math.floor(hours / 24);
  if (days < 30) return days + 'd ago';
  return formatDate(ms);
}
