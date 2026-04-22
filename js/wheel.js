import { $ } from './util.js';
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { openModal } from './modal.js';

const SEGMENT_COLORS = [
  '#1a1f2d', '#232838', '#d4af6a', '#1a1f2d',
  '#7c6cff', '#232838', '#d4af6a', '#1a1f2d'
];
const SEGMENT_LABELS = [
  '10 pts', '50 pts', '100 pts', '25 pts',
  '500 pts', '20 pts', '75 pts', '5 pts'
];
const COOLDOWN_MS = 24 * 60 * 60 * 1000;
const SPIN_DURATION_MS = 4500;

let canvas, ctx;
let rotation = 0;
let spinning = false;

function drawWheel(deg = 0) {
  const size = canvas.width;
  const cx = size / 2, cy = size / 2, r = size / 2 - 4;
  ctx.clearRect(0, 0, size, size);
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate((deg * Math.PI) / 180);

  const n = SEGMENT_LABELS.length;
  const seg = (2 * Math.PI) / n;
  for (let i = 0; i < n; i++) {
    const a0 = i * seg - Math.PI / 2;
    const a1 = a0 + seg;
    const color = SEGMENT_COLORS[i];

    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.arc(0, 0, r, a0, a1);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.06)';
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.save();
    ctx.rotate(a0 + seg / 2);
    ctx.textAlign = 'right';
    ctx.fillStyle = color === '#d4af6a' ? '#1a1408' : '#e8ecf3';
    ctx.font = '600 15px Inter, sans-serif';
    ctx.fillText(SEGMENT_LABELS[i], r - 18, 6);
    ctx.restore();
  }

  ctx.beginPath();
  ctx.arc(0, 0, r, 0, Math.PI * 2);
  ctx.strokeStyle = '#d4af6a';
  ctx.lineWidth = 3;
  ctx.stroke();
  ctx.restore();
}

const easeOutCubic = t => 1 - Math.pow(1 - t, 3);

function remainingCooldown() {
  const user = store.get().user;
  if (!user) return 0;
  return Math.max(0, COOLDOWN_MS - (Date.now() - (user.lastSpin || 0)));
}

export function refreshSpinButton() {
  const btn = $('#spinBtn');
  const user = store.get().user;
  if (!user) { btn.textContent = 'SPIN'; btn.disabled = false; return; }
  const left = remainingCooldown();
  if (left <= 0) { btn.textContent = 'SPIN'; btn.disabled = false; return; }
  const h = Math.floor(left / 3_600_000);
  const m = Math.floor((left % 3_600_000) / 60_000);
  btn.textContent = h > 0 ? `${h}h ${m}m` : `${m}m`;
  btn.disabled = true;
}

function animateTo(idx) {
  return new Promise(resolve => {
    const n = SEGMENT_LABELS.length;
    const segDeg = 360 / n;
    const targetWithin = segDeg / 2;
    const fullTurns = 6 + Math.floor(Math.random() * 3);
    const finalDeg = 360 * fullTurns + (360 - (idx * segDeg + targetWithin));

    const start = rotation;
    const t0 = performance.now();

    function frame(now) {
      const t = Math.min(1, (now - t0) / SPIN_DURATION_MS);
      const eased = easeOutCubic(t);
      rotation = start + (finalDeg - start) * eased;
      drawWheel(rotation);
      if (t < 1) requestAnimationFrame(frame);
      else resolve();
    }
    requestAnimationFrame(frame);
  });
}

async function spin() {
  if (spinning) return;
  const { user } = store.get();
  if (!user) { openModal('register'); toast('Create an account to spin.'); return; }

  spinning = true;
  $('#spinBtn').disabled = true;

  try {
    const result = await api.spin();
    await animateTo(result.index);

    store.set(s => ({
      ...s,
      user: result.user,
      stats: { ...s.stats, spins: (s.stats.spins || 0) + 1 }
    }));

    const parts = [`${result.points} pts`];
    if (result.bonus)       parts.push(`+${result.bonus} ${result.tier}`);
    if (result.streakBonus) parts.push(`+${result.streakBonus} streak`);
    const msg = `You won ${parts.join(' ')} = ${result.total} pts!`;
    const streakNote = (result.streak && result.streak > 1)
      ? ` 🔥 ${result.streak}-day streak.`
      : '';
    $('#lastResult').textContent = msg + streakNote;
    toast(msg + streakNote, 'success');

    // Tell anyone interested that a spin just happened.
    document.dispatchEvent(new CustomEvent('aurum:spin-complete', { detail: result }));
  } catch (err) {
    if (err.status === 429 && err.data && err.data.remainingMs) {
      const mins = Math.ceil(err.data.remainingMs / 60000);
      toast(`Come back in about ${mins >= 60 ? Math.ceil(mins / 60) + 'h' : mins + 'm'}.`);
    } else if (err.status === 401) {
      openModal('login'); toast('Please sign in to spin.');
    } else {
      toast(err.message, 'error');
    }
  } finally {
    spinning = false;
    refreshSpinButton();
  }
}

export function initWheel() {
  canvas = $('#wheel');
  ctx = canvas.getContext('2d');
  drawWheel(0);
  $('#spinBtn').addEventListener('click', spin);
  refreshSpinButton();
  // Keep the cooldown label live.
  setInterval(refreshSpinButton, 60_000);
  store.subscribe(refreshSpinButton);
}
