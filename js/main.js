import { $ } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast , reportError} from './ui.js';
import { initSharedLayout } from './layout.js';
import { initWheel } from './wheel.js';
import { initLeaderboard, refreshLeaderboard } from './leaderboard.js';
import { initRewards, refreshRewards } from './rewards.js';
import { initTasks, refreshTasks } from './tasks.js';
import { initCamroom } from './camroom.js';
import { initUserWidget } from './userWidget.js';

// -------- Global error boundary ---------------------------------
// Any uncaught JS error or unhandled promise rejection in the site
// gets a user-visible toast instead of silently failing, and is
// logged to the console with an [axm] prefix for easier triage.
function safeToast(msg) {
  try {
    toast(msg, 'error');
  } catch {
    /* toast DOM not ready */
  }
}
function safeAlert(msg) {
  // Fallback visual error if toast system fails
  console.error('[axm]', msg);
  try {
    const banner = document.createElement('div');
    banner.style.cssText =
      'position:fixed;top:0;left:0;right:0;background:red;color:white;padding:16px;z-index:99999;font-size:14px;';
    banner.textContent = '[ERROR] ' + msg;
    document.body.appendChild(banner);
  } catch {}
}
window.addEventListener('error', (ev) => {
  console.error('[axm] runtime error:', ev.error || ev.message);
  console.error('[axm] stack:', ev.error?.stack || '(no stack)');
  safeToast('Something went wrong. Please refresh the page.');
});
window.addEventListener('unhandledrejection', (ev) => {
  console.error('[axm] unhandled promise:', ev.reason);
  if (ev.reason?.stack) console.error('[axm] stack:', ev.reason.stack);
  safeToast('A request failed. Please try again.');
});
// Also catch module loading errors
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    if (!window.axmBootstrapped) {
      console.warn('[axm] bootstrap did not complete after DOMContentLoaded');
    }
  });
  setTimeout(() => {
    if (!window.axmBootstrapped) {
      safeAlert('Site modules failed to load. Check browser console.');
    }
  }, 5000);
}

async function bootstrap() {
  initSharedLayout();
  initWheel();
  initLeaderboard();
  initRewards();
  initTasks();
  initCamroom();
  initUserWidget();

  // Initial data load. Don't block UI on failures.
  const [meRes, statsRes] = await Promise.allSettled([api.me(), api.stats()]);
  store.set({
    user: meRes.status === 'fulfilled' ? meRes.value.user : null,
    stats: statsRes.status === 'fulfilled' ? statsRes.value : { members: 0, spins: 0 },
  });
  await Promise.allSettled([refreshLeaderboard(), refreshRewards(), refreshTasks()]);

  // Mark successful bootstrap
  window.axmBootstrapped = true;
  console.log('[axm] bootstrap complete');

  // Handle password reset token
  const params = new URLSearchParams(window.location.search);
  const resetToken = params.get('reset_token');
  if (resetToken) {
    // wait a tick for the DOM to settle
    setTimeout(() => {
      openModal('reset-password');
      const tokenInput = $('#resetPasswordToken');
      if (tokenInput) tokenInput.value = resetToken;
      // remove token from URL cleanly
      window.history.replaceState({}, document.title, window.location.pathname);
    }, 100);
  }
}

bootstrap().catch((err) => {
  console.error('[axm] bootstrap failed:', err);
  console.error('[axm] stack:', err.stack);
  safeAlert('Site failed to initialize. Check console for details.');
});
