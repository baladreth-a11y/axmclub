<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AxMclub.com — Premium Rewards</title>
  <meta name="description" content="A private members club with daily rewards, tiered perks, and hand-picked offers." />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Playfair+Display:wght@600;700&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="styles.css" />
</head>
<body class="is-gated is-age-gated">
  <!-- NAVBAR -->
  <header class="navbar">
    <div class="container nav-inner">
      <a href="#" class="brand" aria-label="AxMclub home">
        <span class="brand-mark">A</span>
        <span class="brand-name">AxMclub<span class="brand-accent">.com</span></span>
      </a>
      <nav class="nav-links" aria-label="Primary">
        <div class="nav-item nav-dropdown">
          <button type="button" class="nav-link nav-dropdown-toggle" aria-haspopup="true">
            Support &amp; Rewards <span class="chev" aria-hidden="true">▾</span>
          </button>
          <div class="nav-dropdown-menu" role="menu">
            <a role="menuitem" href="/play.html#tasks">Daily tasks</a>
            <a role="menuitem" href="/play.html#roulette">Roulette</a>
            <a role="menuitem" href="/marketplace.html#rewards">Rewards tiers</a>
          </div>
        </div>
        <a id="navPlayers" class="nav-link" href="/players.html">Players</a>
        <a id="navCam" class="nav-link" href="/cam.html">Cam Room</a>
        <a id="navSupporters" class="nav-link" href="/supporters.html">Top Supporters</a>
        <a id="navMarketplace" class="nav-link" href="/marketplace.html">Marketplace</a>
        <a id="navRoster" class="nav-link" href="/supporters.html#party-roster">AxM Party Roster</a>
        <a id="navModelLink" class="nav-link hidden" href="/model.html">Model dashboard</a>
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
    </div>
  </header>

  <!-- GATE OVERLAY: two stages (age verification -> auth). -->
  <div id="gate" class="gate" role="dialog" aria-modal="true" aria-labelledby="gateTitle">

    <!-- Stage A: 18+ age verification (blur stays until confirmed) -->
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

    <!-- Stage B: auth prompt (blur gone, but navigation stays locked) -->
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
  </div>

  <!-- AXM PROFILES BANNER (lead element after gate) -->
  <section class="profiles-banner" aria-labelledby="profilesBannerTitle">
    <div class="container profiles-banner-inner">
      <span class="eyebrow">Featured</span>
      <h2 id="profilesBannerTitle" class="profiles-banner-title">AxM<span class="brand-accent">cam</span>Players</h2>
      <p class="muted">The roster behind the club — real models, real shows. Connect directly on Telegram, Snap or their webcam channel.</p>
    </div>
  </section>

  <!-- TOP STRIP: signed-in-only event + stats widget. Hidden for
       anonymous visitors via `body.is-anon .top-strip { display:none }`. -->
  <section id="top-strip" class="section top-strip" aria-label="Announcements and your stats">
    <div class="container top-strip-inner">

      <!-- Left: upcoming event / fallback to next party -->
      <aside class="event-panel" aria-labelledby="eventPanelTitle">
        <span class="eyebrow">Up next</span>
        <h3 id="eventPanelTitle">Winter Lights</h3>
        <p class="muted">Fri · Dec 12 · Hosted by Nova</p>
        <p class="event-body">
          The cam-room after-party. If a Special Event is scheduled we'll
          feature it here — otherwise, it's the next stop on the Party Roster.
        </p>
        <div class="event-actions">
          <a class="btn btn-outline" href="/supporters.html#party-roster">See the roster</a>
        </div>
      </aside>

      <!-- Right: user profile stats widget -->
      <aside class="stats-widget" aria-labelledby="statsWidgetTitle">
        <h3 id="statsWidgetTitle" class="stats-widget-title">Your stats</h3>
        <dl class="stats-widget-grid">
          <div class="stat-row">
            <dt>Rank</dt>
            <dd id="widgetRank">—</dd>
          </div>
          <div class="stat-row">
            <dt>Level</dt>
            <dd id="widgetLevel">—</dd>
          </div>
          <div class="stat-row">
            <dt>Points <small>(total)</small></dt>
            <dd id="widgetPoints" class="is-points">—</dd>
          </div>
          <div class="stat-row">
            <dt>Tokens <small>(total)</small></dt>
            <dd id="widgetTokens" class="is-tokens">—</dd>
          </div>
        </dl>
        <div class="stats-widget-actions">
          <button id="widgetGetTokens" class="btn btn-primary" type="button">Get tokens</button>
          <button id="widgetMakeOffer" class="btn btn-outline"  type="button">Make offer</button>
        </div>
        <p class="fine-print">
          Rank is granted by a model after a 10-min webcam session.
          Points come from roulette / rewards / model tips. Tokens are
          the club's real currency and can be bought only.
        </p>
      </aside>

    </div>
  </section>

  <!-- HERO (CTA + counters; sits below the gallery on the home page) -->
  <section class="hero">
    <div class="container hero-inner">
      <div class="hero-copy">
        <span class="eyebrow">Premium members club</span>
        <h1>Spin. Earn. <span class="gold">Belong.</span></h1>
        <p class="lead">
          Join AxMclub and unlock a curated rewards program, a daily spin
          roulette, and members-only perks — built with a focus on quality
          over noise.
        </p>
        <div class="hero-cta">
          <button class="btn btn-primary btn-lg" onclick="openModal('register')">Create free account</button>
          <a href="/players.html" class="btn btn-outline btn-lg">Browse models</a>
        </div>
        <dl class="hero-stats">
          <div><dt>Members</dt><dd id="statMembers">2,418</dd></div>
          <div><dt>Spins</dt><dd id="statSpins">14,902</dd></div>
          <div><dt>Rating</dt><dd>4.9★</dd></div>
        </dl>
      </div>

      <aside class="hero-visual" aria-hidden="true">
        <div class="preview-glow"></div>
        <div class="preview-card">
          <header class="preview-head">
            <span class="preview-avatar">A</span>
            <div class="preview-ident">
              <strong>Alex Carter</strong>
              <span>Member #00241</span>
            </div>
            <span class="badge badge-gold">Gold</span>
          </header>
          <div class="preview-balance">
            <span class="label">Balance</span>
            <div class="amount">1,245<small>pts</small></div>
          </div>
          <div class="preview-progress">
            <div class="progress-head">
              <span>Progress to <b>Platinum</b></span>
              <span>745 / 1,000</span>
            </div>
            <div class="progress-bar"><div class="progress-fill" style="width: 74%"></div></div>
          </div>
          <div class="preview-footer">
            <span class="badge badge-solid">Daily spin ready</span>
            <span class="preview-meta">+15% tier bonus</span>
          </div>
        </div>
      </aside>
    </div>
  </section>

  <!-- DYNAMIC MODEL GALLERY -->
  <!-- Cards are rendered into #modelsGrid by js/models.js from
       GET /api/models. The list is real model accounts only — no
       hard-coded fillers. Public to all visitors after the age gate;
       per-model profile views are gated to verified signed-in users. -->
  <section id="players" class="section players-section">
    <div class="container">
      <div id="modelsGrid" class="models-grid">
        <p class="lb-empty">Loading models…</p>
      </div>
    </div>
  </section>

  <!-- CTA -->
  <section class="section section-cta">
    <div class="container cta-inner">
      <h2>Ready to belong to something sharper?</h2>
      <p class="muted">Free to join. No spam. Leave anytime.</p>
      <button class="btn btn-primary btn-lg" onclick="openModal('register')">Create my account</button>
    </div>
  </section>

  <!-- FOOTER -->
  <footer class="footer">
    <div class="container footer-inner">
      <div class="brand">
        <span class="brand-mark">A</span>
        <span class="brand-name">AxMclub<span class="brand-accent">.com</span></span>
      </div>
      <p>© <span id="year"></span> AxMclub.com. All rights reserved.</p>
    </div>
  </footer>

  <!-- MODALS -->
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

      <div class="modal-view hidden onboarding" data-view="onboarding">
        <span class="eyebrow">Next steps</span>
        <h3 id="onboardingTitle">Welcome to AxMclub</h3>
        <p id="onboardingIntro" class="muted">Your account is ready. Here are the fastest ways to get value from the club.</p>
        <ol class="onboarding-list">
          <li id="onboardingStepAccount" class="onboarding-step">
            <span class="onboarding-step-marker" aria-hidden="true"></span>
            <div>
              <strong>Account created</strong>
              <span>Your member profile is active and saved for this device.</span>
            </div>
          </li>
          <li id="onboardingStepVerify" class="onboarding-step">
            <span class="onboarding-step-marker" aria-hidden="true"></span>
            <div>
              <strong>Verify your email</strong>
              <span>Unlock full model profiles and keep your account recoverable.</span>
            </div>
          </li>
          <li id="onboardingStepSpin" class="onboarding-step">
            <span class="onboarding-step-marker" aria-hidden="true"></span>
            <div>
              <strong>Claim your daily spin</strong>
              <span>Start earning points toward rewards and tier progress.</span>
            </div>
          </li>
          <li id="onboardingStepExplore" class="onboarding-step">
            <span class="onboarding-step-marker" aria-hidden="true"></span>
            <div>
              <strong>Browse the roster</strong>
              <span>Find models, socials, and the next cam-room destination.</span>
            </div>
          </li>
        </ol>
        <div class="onboarding-actions">
          <button id="onboardingVerifyBtn" class="btn btn-primary" type="button">Send verification email</button>
          <a class="btn btn-outline" href="/play.html#roulette">Daily spin</a>
          <a class="btn btn-outline" href="/players.html">Browse models</a>
        </div>
        <button id="onboardingDoneBtn" class="btn btn-ghost btn-block" type="button">I'll do this later</button>
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
              <span class="badge badge-muted" id="profileVerified">Email unverified</span>
              <span class="badge badge-accent hidden" id="profileStreak">🔥 0-day streak</span>
            </div>
          </div>
        </div>
        <div class="profile-stats">
          <div class="profile-stat">
            <span class="label">Rank</span>
            <strong id="profileRank">Unranked</strong>
          </div>
          <div class="profile-stat">
            <span class="label">Level</span>
            <strong id="profileLevel">0</strong>
          </div>
          <div class="profile-stat">
            <span class="label">Points</span>
            <strong id="profilePoints">0</strong>
          </div>
          <div class="profile-stat">
            <span class="label">Tokens</span>
            <strong id="profileTokens">0</strong>
          </div>
        </div>
        <div class="profile-meta-grid">
          <div>
            <span class="label">Member since</span>
            <strong id="profileJoined">—</strong>
          </div>
          <div>
            <span class="label">Last spin</span>
            <strong id="profileLastSpin">Never</strong>
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
        <div class="profile-actions">
          <button class="btn btn-outline btn-block" onclick="closeModal()">Close</button>
          <button id="profileLogout" class="btn btn-ghost btn-block">Sign out</button>
        </div>
      </div>
    </div>
  </div>

  <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>

  <script type="module" src="js/main.js"></script>
  <script>
    (function(){
      var url = "https://crxcra.com/cams-widget-ext/im_jerky?lang=en&mode=prerecorded&outlinkUrl=https://t.crdtg2.com/409509/7234?bo=2753%2C2754%2C2755%2C2756&aff_sub5=SF_006OG000004lmDN&aff_sub4=AT_0018";
      var s = document.createElement('script');
      s.defer = true;
      s.src = url;
      var timer = setTimeout(function(){ if(s.parentNode) s.parentNode.removeChild(s); console.warn('Third-party script timed out and was removed:', url); }, 3000);
      s.onload = function(){ clearTimeout(timer); };
      s.onerror = function(){ clearTimeout(timer); console.warn('Third-party script failed to load:', url); };
      document.head.appendChild(s);
    })();
  </script>
</body>
</html>
