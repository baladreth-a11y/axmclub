// Shared site chrome (navbar, gate overlay, modals, footer, toast).
//
// Each page that wants the standard layout includes hosts:
//   <header id="navHost"></header>
//   <div    id="gateHost"></div>
//   <!-- page main content here -->
//   <div    id="modalHost"></div>
//   <footer id="footerHost"></footer>
//   <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
//
// Then in its main module:
//   import { initSharedLayout } from './layout.js';
//   initSharedLayout({ activePage: 'cam' });
//
// `activePage` highlights the matching nav link. Pass null on the home page.
//
// initSharedLayout returns nothing; it just wires up the standard UI:
// modal, gate, header, hero stats (only if #statMembers exists), and auth.
// Page-specific initializers (wheel, rewards, tasks, etc.) stay the
// responsibility of each page's main.js.
import { $ } from './util.js';
import { store } from './store.js';
import { initModal } from './modal.js';
import { initGate } from './gate.js';
import { initHeader } from './header.js';
import { initHeroStats } from './heroStats.js';
import { initAuth } from './auth.js';
import { initModels } from './models.js';
import { initVerifyBanner } from './verify.js';
import { initFeedback } from './feedback.js';
import { initCommunicator } from './communicator.js';
import { api } from './api.js';

// ---- Markup ---------------------------------------------------------
// Navbar. The "Model dashboard" link is hidden by default and revealed
// by the store subscription below when the signed-in user has
// accountType === 'model'.
function navMarkup(activePage) {
  const isActive = name => (activePage === name ? ' aria-current="page"' : '');
  return `
    <div class="container nav-inner">
      <a href="/" class="brand" aria-label="AxMclub home">
        <span class="brand-mark">A</span>
        <span class="brand-name">AxMclub<span class="brand-accent">.com</span></span>
      </a>
      <nav class="nav-links" aria-label="Primary">
        <a class="nav-link" href="/players.html"${isActive('players')}>Players</a>
        <a class="nav-link" href="/play.html"${isActive('play')}>Play</a>
        <a class="nav-link" href="/cam.html"${isActive('cam')}>Cam Room</a>
        <a class="nav-link" href="/marketplace.html"${isActive('marketplace')}>Marketplace</a>
        <a class="nav-link" href="/supporters.html"${isActive('supporters')}>Supporters</a>
        <a id="navModelLink" class="nav-link hidden" href="/model.html"${isActive('model')}>Model dashboard</a>
      </nav>
      <div class="nav-actions">
        <button id="openLogin" class="btn btn-ghost">Sign in</button>
        <button id="openRegister" class="btn btn-primary">Join free</button>
        <div id="userChip" class="user-chip hidden">
          <button id="openProfile" class="user-chip-btn" title="View profile">
            <span class="user-initial" id="userInitial">A</span>
            <span id="userName">Member</span>
          </button>
          <button id="logoutBtn" class="user-logout" title="Sign out" aria-label="Sign out">⎋</button>
        </div>
      </div>
    </div>`;
}

const gateMarkup = `
  <div id="gate" class="gate" role="dialog" aria-modal="true" aria-labelledby="gateTitle">
    <div class="gate-card" data-stage="age">
      <span class="eyebrow">Age verification</span>
      <h2 id="gateTitle">Are you 18 or older?</h2>
      <p class="muted">
        AxMclub.com hosts members-only adult content. By continuing you
        confirm you are at least 18 years old and consent to viewing this
        material.
      </p>
      <div class="gate-actions">
        <button id="gateAgeYes" class="btn btn-primary btn-lg">Yes, I'm 18+</button>
        <a class="btn btn-outline btn-lg" href="https://www.google.com" rel="noopener noreferrer">No, take me away</a>
      </div>
      <p class="fine-print">Your confirmation is saved on this device.</p>
    </div>
    <div class="gate-card hidden" data-stage="auth">
      <span class="eyebrow">Members only</span>
      <h2>Sign in to explore the club</h2>
      <p class="muted">
        Create a free Supporter account or sign in. The site stays locked
        for navigation until you do.
      </p>
      <div class="gate-actions">
        <button class="btn btn-primary btn-lg" onclick="openModal('register')">Create Supporter account</button>
        <button class="btn btn-outline btn-lg" onclick="openModal('login')">Sign in</button>
      </div>
      <p class="fine-print">Model accounts are invite-only — coming soon.</p>
    </div>
  </div>`;

const modalMarkup = `
  <div id="modalBackdrop" class="modal-backdrop hidden">
    <div class="modal" role="dialog" aria-modal="true">
      <button class="modal-close" onclick="closeModal()" aria-label="Close">×</button>

      <div class="modal-view" data-view="register">
        <h3>Create your account</h3>
        <p class="muted">Takes 10 seconds. Stored securely on the server.</p>
        <form id="registerForm" class="form">
          <div class="form-field">
            <span class="form-field-label">I'm joining as…</span>
            <div class="acct-segment">
              <label class="acct-option">
                <input type="radio" name="accountType" value="supporter" checked />
                <span>Supporter</span>
              </label>
              <label class="acct-option is-disabled" title="Model accounts are invite-only — coming soon">
                <input type="radio" name="accountType" value="model" disabled />
                <span>Model <i>(soon)</i></span>
              </label>
            </div>
          </div>
          <label>Display name
            <input name="name" type="text" required minlength="2" placeholder="e.g. Alex Carter" autocomplete="name" />
          </label>
          <label>Email
            <input name="email" type="email" required placeholder="you@domain.com" autocomplete="email" />
          </label>
          <label>Password
            <input name="password" type="password" required minlength="4" placeholder="At least 4 characters" autocomplete="new-password" />
          </label>
          <button class="btn btn-primary btn-block" type="submit">Create Supporter account</button>
          <p class="switch">Already a member? <a href="#" onclick="switchView('login'); return false;">Sign in</a></p>
        </form>
      </div>

      <div class="modal-view hidden" data-view="login">
        <h3>Welcome back</h3>
        <p class="muted">Enter your email and password.</p>
        <form id="loginForm" class="form">
          <label>Email
            <input name="email" type="email" required placeholder="you@domain.com" autocomplete="email" />
          </label>
          <label>Password
            <input name="password" type="password" required placeholder="Your password" autocomplete="current-password" />
          </label>
          <button class="btn btn-primary btn-block" type="submit">Sign in</button>
          <p class="switch">New here? <a href="#" onclick="switchView('register'); return false;">Create account</a></p>
        </form>
      </div>

      <div class="modal-view hidden" data-view="tokens">
        <h3>Get tokens</h3>
        <p class="muted">Tokens are the club's real currency. Pick a pack below.</p>
        <form id="tokensForm" class="form">
          <div class="token-packs" role="radiogroup" aria-label="Token pack">
            <label class="token-pack">
              <input type="radio" name="amount" value="100" checked />
              <span><strong>100</strong> tokens<small>$9.99</small></span>
            </label>
            <label class="token-pack">
              <input type="radio" name="amount" value="500" />
              <span><strong>500</strong> tokens<small>$39.99</small></span>
            </label>
            <label class="token-pack">
              <input type="radio" name="amount" value="1200" />
              <span><strong>1,200</strong> tokens<small>$79.99</small></span>
            </label>
            <label class="token-pack">
              <input type="radio" name="amount" value="3000" />
              <span><strong>3,000</strong> tokens<small>$179.99</small></span>
            </label>
          </div>
          <button class="btn btn-primary btn-block" type="submit">Confirm purchase</button>
          <p class="fine-print">Demo: no real payment is processed.</p>
        </form>
      </div>

      <div class="modal-view hidden" data-view="offer">
        <h3>Make an offer</h3>
        <p class="muted">Propose a rank, a stream request, or a custom deal. The host team reviews every offer.</p>
        <form id="offerForm" class="form">
          <label>To (model name, optional)
            <input name="target" type="text" placeholder="e.g. Nova" />
          </label>
          <label>Your offer
            <textarea name="message" rows="5" required minlength="10" placeholder="What are you looking for and what are you offering in return?"></textarea>
          </label>
          <button class="btn btn-primary btn-block" type="submit">Send offer</button>
        </form>
      </div>

      <div class="modal-view hidden" data-view="profile">
        <div class="profile-header">
          <div class="profile-avatar" id="profileAvatar">A</div>
          <div class="profile-ident">
            <h3 id="profileName">Member</h3>
            <p class="muted" id="profileEmail">email@example.com</p>
            <div class="profile-badges">
              <span class="badge badge-gold" id="profileTier">Silver tier</span>
              <span class="badge badge-accent hidden" id="profileStreak">🔥 0-day streak</span>
            </div>
          </div>
        </div>
        <div class="profile-stats">
          <div class="profile-stat">
            <span class="label">Balance</span>
            <strong id="profilePoints">0</strong>
          </div>
          <div class="profile-stat">
            <span class="label">Member since</span>
            <strong id="profileJoined">—</strong>
          </div>
          <div class="profile-stat">
            <span class="label">Last spin</span>
            <strong id="profileLastSpin">—</strong>
          </div>
        </div>
        <div class="profile-progress">
          <div class="progress-head">
            <span class="muted">Progress to <b id="profileNextTier">Gold</b></span>
            <span id="profileProgressText">0 / 500</span>
          </div>
          <div class="progress-bar"><div id="profileProgressFill" class="progress-fill"></div></div>
        </div>
        <div class="profile-activity-wrap">
          <h4 class="profile-activity-title">Recent activity</h4>
          <ul id="profileActivity" class="profile-activity">
            <li class="activity-empty">Loading activity…</li>
          </ul>
        </div>
        <div class="profile-dm-policy">
          <span class="profile-dm-policy-label">Who can DM me</span>
          <div class="dm-policy-segment" role="radiogroup" aria-label="DM policy">
            <label class="dm-policy-option">
              <input type="radio" name="dmPolicy" value="open" />
              <span>Open</span>
            </label>
            <label class="dm-policy-option">
              <input type="radio" name="dmPolicy" value="mutual" />
              <span>Mutual</span>
            </label>
            <label class="dm-policy-option">
              <input type="radio" name="dmPolicy" value="closed" />
              <span>Closed</span>
            </label>
          </div>
        </div>
        <div class="profile-actions">
          <button class="btn btn-outline btn-block" onclick="closeModal()">Close</button>
          <button id="profileLogout" class="btn btn-ghost btn-block">Sign out</button>
        </div>
      </div>
    </div>
  </div>`;

const footerMarkup = `
  <div class="container footer-inner">
    <div class="brand">
      <span class="brand-mark">A</span>
      <span class="brand-name">AxMclub<span class="brand-accent">.com</span></span>
    </div>
    <p>© <span id="year"></span> AxMclub.com. All rights reserved.</p>
  </div>`;

// ---- Public API ----------------------------------------------------
export function initSharedLayout({ activePage = null } = {}) {
  const navHost    = $('#navHost');
  const gateHost   = $('#gateHost');
  const modalHost  = $('#modalHost');
  const footerHost = $('#footerHost');

  if (navHost) {
    navHost.classList.add('navbar');
    navHost.innerHTML = navMarkup(activePage);
  }
  if (gateHost)   gateHost.outerHTML   = gateMarkup;
  if (modalHost)  modalHost.outerHTML  = modalMarkup;
  if (footerHost) {
    footerHost.classList.add('footer');
    footerHost.innerHTML = footerMarkup;
  }

  const yearEl = $('#year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  initModal();
  initGate();
  initHeader();
  if ($('#statMembers')) initHeroStats();
  initAuth();
  initVerifyBanner();
  // Pages that include a `#modelsGrid` placeholder get the dynamic
  // gallery rendered into it. Otherwise this is a no-op.
  initModels();
  // Always-on Feedback & Ideas FAB (bottom-right). Mounted on every
  // page that uses initSharedLayout. Submissions land in db.feedback.
  initFeedback();
  // Always-on Communicator (bottom-left). Lazy: presence + threads only
  // poll once a signed-in user is set on the store.
  initCommunicator();

  // Keep the DM-policy radio in the profile modal in sync with the
  // signed-in user's policy and persist edits via api.chatPolicy.
  const dmRadios = document.querySelectorAll('.dm-policy-segment input[name="dmPolicy"]');
  if (dmRadios.length) {
    const applyPolicy = state => {
      const policy = (state.user && state.user.dmPolicy) || 'open';
      dmRadios.forEach(r => { r.checked = (r.value === policy); });
    };
    applyPolicy(store.get());
    store.subscribe(applyPolicy);
    dmRadios.forEach(r => r.addEventListener('change', async () => {
      if (!r.checked) return;
      try {
        const res = await api.chatPolicy(r.value);
        if (res && res.user) store.set({ user: res.user });
      } catch (err) {
        console.error('[axm] dmPolicy update failed:', err);
      }
    }));
  }

  // Toggle the "Model dashboard" nav link based on accountType.
  const modelLink = $('#navModelLink');
  if (modelLink) {
    const apply = state => {
      const u = state.user;
      const show = !!u && u.accountType === 'model';
      modelLink.classList.toggle('hidden', !show);
    };
    apply(store.get());
    store.subscribe(apply);
  }
}

// Helper to redirect away from a page if the visitor isn't a model.
// Returns a promise that resolves when the redirect is decided. Pages
// that need a model account call this BEFORE wiring up dashboard logic.
export async function requireModelAccount(redirectTo = '/') {
  // Wait for /api/me to resolve.
  try {
    const { user } = await (await fetch('/api/me', { credentials: 'include' })).json();
    if (!user) {
      // Anonymous: send to home, gate will catch them.
      window.location.replace(redirectTo);
      return null;
    }
    if (user.accountType !== 'model') {
      // Wrong type: bounce with an alert hash so we can flash a toast.
      window.location.replace(redirectTo + '?why=model-only');
      return null;
    }
    return user;
  } catch {
    window.location.replace(redirectTo);
    return null;
  }
}
