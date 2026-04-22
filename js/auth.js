import { $ } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { openModal, closeModal } from './modal.js';
import { refreshLeaderboard } from './leaderboard.js';

async function doLogout() {
  try { await api.logout(); } catch { /* ignore */ }
  store.set({ user: null });
  closeModal();
  $('#lastResult').textContent = 'Sign in and press SPIN to try your luck.';
  refreshLeaderboard();
  toast('Signed out.');
}

async function refreshStats() {
  try {
    const s = await api.stats();
    store.set({ stats: s });
  } catch { /* keep previous */ }
}

export function initAuth() {
  $('#registerForm').addEventListener('submit', async e => {
    e.preventDefault();
    const fd = new FormData(e.target);
    try {
      const { user } = await api.register({
        name: fd.get('name'),
        email: fd.get('email'),
        password: fd.get('password')
      });
      store.set({ user });
      closeModal(); e.target.reset();
      refreshStats();
      refreshLeaderboard();
      toast('Welcome to AxMclub!', 'success');
    } catch (err) { toast(err.message, 'error'); }
  });

  $('#loginForm').addEventListener('submit', async e => {
    e.preventDefault();
    const fd = new FormData(e.target);
    try {
      const { user } = await api.login({
        email: fd.get('email'),
        password: fd.get('password')
      });
      store.set({ user });
      closeModal(); e.target.reset();
      refreshLeaderboard();
      toast(`Welcome back, ${user.name}.`, 'success');
    } catch (err) { toast(err.message, 'error'); }
  });

  $('#openLogin').addEventListener('click', () => openModal('login'));
  $('#openRegister').addEventListener('click', () => openModal('register'));
  $('#openProfile').addEventListener('click', () => {
    if (store.get().user) openModal('profile');
  });
  $('#logoutBtn').addEventListener('click', doLogout);
  $('#profileLogout').addEventListener('click', doLogout);
}
