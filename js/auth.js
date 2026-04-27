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
  // #lastResult lives on the roulette section. Pages that don't render
  // the wheel (cam, marketplace, model dashboard, ...) won't have it.
  const lr = $('#lastResult');
  if (lr) lr.textContent = 'Sign in and press SPIN to try your luck.';
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
  // Many of these elements only exist if the page mounted the modal +
  // navbar partials. Guard each binding so we can call initAuth() from
  // any page.
  const onSubmit = (sel, handler) => {
    const el = $(sel);
    if (el) el.addEventListener('submit', handler);
  };
  const onClick = (sel, handler) => {
    const el = $(sel);
    if (el) el.addEventListener('click', handler);
  };
  onSubmit('#registerForm', async e => {
    e.preventDefault();
    const fd = new FormData(e.target);
    try {
      const { user } = await api.register({
        name: fd.get('name'),
        email: fd.get('email'),
        password: fd.get('password'),
        accountType: fd.get('accountType') || 'supporter'
      });
      store.set({ user });
      closeModal(); e.target.reset();
      refreshStats();
      refreshLeaderboard();
      toast('Welcome to AxMclub!', 'success');
    } catch (err) { toast(err.message, 'error'); }
  });

  onSubmit('#loginForm', async e => {
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

  onClick('#openLogin',     () => openModal('login'));
  onClick('#openRegister',  () => openModal('register'));
  onClick('#openProfile',   () => {
    if (store.get().user) openModal('profile');
  });
  onClick('#logoutBtn',     doLogout);
  onClick('#profileLogout', doLogout);
}
