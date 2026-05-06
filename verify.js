import { $, escapeHtml } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { openModal } from './modal.js';

function formatDuration(ms) {
  if (ms <= 0) return 'ready';
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400);
  if (d > 0) return d + 'd';
  const h = Math.floor(s / 3600);
  if (h > 0) return h + 'h';
  const m = Math.floor(s / 60);
  if (m > 0) return m + 'm';
  return s + 's';
}

function cardHtml(t, signedIn) {
  const locked = !t.available;
  let label;
  if (!signedIn) {
    label = 'Sign in to claim';
  } else if (t.cooldownMs === 0 && t.claimedAt > 0) {
    label = 'Claimed';
  } else if (t.cooldownRemaining > 0) {
    label = 'Ready in ' + formatDuration(t.cooldownRemaining);
  } else {
    label = 'Claim +' + t.reward + ' pts';
  }
  return `
    <article class="task-card${locked ? ' is-locked' : ''}" data-task-id="${escapeHtml(t.id)}">
      <header class="task-head">
        <h3>${escapeHtml(t.title)}</h3>
        <span class="badge badge-gold">+${t.reward} pts</span>
      </header>
      <p class="task-desc">${escapeHtml(t.description)}</p>
      <footer class="task-foot">
        <span class="task-cadence">${t.cooldownMs === 0 ? 'One-time' : ('Every ' + formatDuration(t.cooldownMs))}</span>
        <button
          class="btn ${locked ? 'btn-outline' : 'btn-primary'} task-claim"
          data-task-id="${escapeHtml(t.id)}"
          ${locked ? 'disabled' : ''}>
          ${escapeHtml(label)}
        </button>
      </footer>
    </article>`;
}

function render(state) {
  const list = state.tasks || [];
  const signedIn = !!state.user;
  $('#tasksGrid').innerHTML = list.length
    ? list.map(t => cardHtml(t, signedIn)).join('')
    : '<p class="lb-empty">No tasks right now. Check back soon.</p>';
}

export async function refreshTasks() {
  try {
    const data = await api.tasks();
    store.set({ tasks: data.tasks || [] });
  } catch {
    $('#tasksGrid').innerHTML = '<p class="lb-empty">Could not load tasks.</p>';
  }
}

async function claim(taskId) {
  if (!store.get().user) {
    openModal('login');
    toast('Sign in to claim tasks.');
    return;
  }
  try {
    const res = await api.claimTask(taskId);
    store.set(state => ({ ...state, user: res.user }));
    refreshTasks();
    toast(`+${res.reward} pts \u2014 ${res.title}`, 'success');
  } catch (err) {
    if (err.status === 429 && err.data && err.data.remainingMs) {
      toast('On cooldown \u2014 back in ' + formatDuration(err.data.remainingMs));
      refreshTasks();
    } else if (err.status === 409) {
      toast(err.message);
      refreshTasks();
    } else {
      toast(err.message, 'error');
    }
  }
}

export function initTasks() {
  store.subscribe(render);

  $('#tasksGrid').addEventListener('click', e => {
    const btn = e.target.closest('.task-claim');
    if (!btn || btn.disabled) return;
    claim(btn.dataset.taskId);
  });

  // Re-fetch when the user changes.
  let prevUserEmail;
  store.subscribe(state => {
    const email = state.user ? state.user.email : null;
    if (email !== prevUserEmail) {
      prevUserEmail = email;
      refreshTasks();
    }
  });
}
