import { $ } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { initModal } from './modal.js';
import { initHeader } from './header.js';
import { initHeroStats } from './heroStats.js';
import { initWheel } from './wheel.js';
import { initLeaderboard, refreshLeaderboard } from './leaderboard.js';
import { initRewards, refreshRewards } from './rewards.js';
import { initProfile } from './profile.js';
import { initAuth } from './auth.js';
import { initTasks, refreshTasks } from './tasks.js';
import { initCamroom } from './camroom.js';
import { initGate } from './gate.js';
import { initUserWidget } from './userWidget.js';

async function bootstrap() {
  $('#year').textContent = new Date().getFullYear();

  initModal();
  initGate();
  initHeader();
  initHeroStats();
  initWheel();
  initLeaderboard();
  initRewards();
  initTasks();
  initCamroom();
  initProfile();
  initAuth();
  initUserWidget();

  // Initial data load. Don't block UI on failures.
  const [meRes, statsRes] = await Promise.allSettled([api.me(), api.stats()]);
  store.set({
    user: meRes.status === 'fulfilled' ? meRes.value.user : null,
    stats: statsRes.status === 'fulfilled' ? statsRes.value : { members: 0, spins: 0 }
  });
  await Promise.allSettled([refreshLeaderboard(), refreshRewards(), refreshTasks()]);
}

bootstrap();
