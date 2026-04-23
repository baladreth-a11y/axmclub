# AxMclub.com

A members club website — professional design, daily spin roulette, tiered
rewards — built with no dependencies. Backend is a single PowerShell script
using the built-in `HttpListener`; frontend is plain ES modules.

## Run it

Double-click `start.bat`, or from a PowerShell window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
# Different port:
powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1 -Port 8080
```

Then open <http://localhost:5173>.

## Project layout

```
lucky-site/
├── server.ps1          # Backend — HttpListener + JSON DB
├── start.bat           # One-click launcher
├── e2e-test.ps1        # End-to-end test harness (see below)
├── index.html          # Single static page
├── styles.css          # Design system + components (uses @layer)
├── js/                 # Frontend ES modules
│   ├── main.js         #   entry point, bootstraps init + initial fetch
│   ├── api.js          #   fetch client + named endpoint methods
│   ├── store.js        #   tiny reactive store (get / set / subscribe)
│   ├── util.js         #   $, escapeHtml, tier math, date formatting
│   ├── ui.js           #   toast
│   ├── modal.js        #   open/close/switch, registerView()
│   ├── header.js       #   user chip + balance + tier highlight
│   ├── heroStats.js    #   live stats counters
│   ├── wheel.js        #   canvas wheel + server-authoritative spin
│   ├── leaderboard.js  #   top-10 list render + auto-refresh
│   ├── profile.js      #   profile modal content
│   └── auth.js         #   register/login/logout form handlers
├── data/               # Auto-created: db.json lives here
└── README.md
```

## Architecture overview

```
             ┌──────────────┐
             │   api.js     │  ← one fetch helper, one method per endpoint
             └──────┬───────┘
                    │
        ┌───────────▼───────────┐
        │        store.js       │  ← reactive store (user, stats, leaderboard)
        └───────────┬───────────┘
                    │ subscribe()
     ┌──────────────┼──────────────┬──────────────┬──────────────┐
     ▼              ▼              ▼              ▼              ▼
header.js      heroStats.js   wheel.js      leaderboard.js   profile.js
(user chip,    (stats row)    (canvas +      (rows + medals) (modal view,
 balance)                     spin flow)                      registered via
                                                              modal.registerView)

     auth.js   ── form handlers dispatch calls to api + store.set()
     modal.js  ── owns open/close + data-view-based switching
     main.js   ── init() wires everything and triggers initial load
```

**Principles**
- `store.js` is the single source of truth. Every render module subscribes; no module calls another module's render directly.
- `api.js` is the only place that knows URLs and `fetch` options.
- `modal.js` supports registering views by name (`registerView('profile', { onOpen })`) so feature modules self-register.
- Custom DOM events (`axm:spin-complete`) decouple cross-module triggers (e.g., leaderboard refreshes itself on spin without the wheel knowing about it).

## Adding a new feature in 3 steps

Example: "referral codes"

1. **Backend:** add the endpoint in `server.ps1` — new branches under the `switch` in `Handle-Api` (e.g. `POST /api/referral/claim`, `GET /api/referral/list`).
2. **Client API:** add one method per endpoint in `js/api.js`:
   ```js
   claimReferral: code => request('/api/referral/claim', { method: 'POST', body: { code } }),
   listReferrals: ()   => request('/api/referral/list')
   ```
3. **UI module:** create `js/referrals.js`, subscribe to the store if it needs user state, render into an element you added to `index.html`, and call `initReferrals()` from `js/main.js`. If your feature is a modal, use `registerView('referrals', { onOpen })` and open it with `openModal('referrals')`.

No other files need to change.

## API surface (backend)

- `POST /api/register` — `{ name, email, password }` → `{ user }` + Set-Cookie
- `POST /api/login`    — `{ email, password }` → `{ user }` + Set-Cookie
- `POST /api/logout`   — clears the cookie
- `GET  /api/me`       — `{ user | null }`
- `GET  /api/stats`    — `{ members, spins }`
- `POST /api/spin`     — `{ index, label, points, bonus, total, tier, user }`
- `GET  /api/leaderboard` — `{ leaderboard: [{ name, points, tier }] }` (top 10)

## Design system

- **Tokens** in `styles.css` inside `@layer tokens`: colors, `--space-1..10`, radii, shadows, motion.
- **Single accent**: gold (`--gold`). `--accent` (purple) is used only for the Platinum tier badge.
- **Shared `.badge`** component with variants (`.badge-gold`, `.badge-accent`, `.badge-muted`, `.badge-solid`) — use it instead of one-off pill styles.
- **Typography**: `Playfair Display` for display headings, `Inter` for UI text.
- **Accessibility**: global `:focus-visible` gold ring, `prefers-reduced-motion` escape hatch, smooth scroll with a graceful fallback.

## End-to-end testing

`e2e-test.ps1` starts an isolated server on port 5175 with a fresh DB, runs
34 checks covering registration, spin flow, cooldown, anonymous/wrong-password
rejection, leaderboard ordering, logout/login round-trip, and static files,
then cleans up. Run with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\e2e-test.ps1
```

Results are also written to `e2e-results.log`. Exit code is non-zero on failure.

## Deploy (Option A: Windows VPS + Caddy)
This is the path for a solo operator running one node with automatic HTTPS.
Artifacts live under `deploy/`:
- `deploy/bootstrap-vps.ps1` — **one-shot installer**: prereqs + clone + service + Caddy + backup task.
- `deploy/Caddyfile` — reverse proxy + Let's Encrypt TLS template (domain is rewritten by the bootstrap).
- `deploy/install-service.ps1` — installs `server.ps1` as a Windows service via NSSM (idempotent).
- `deploy/backup-db.ps1` — nightly snapshot + rotation for `data/db.json`.
### One-shot bootstrap (recommended)
From an **elevated PowerShell** on the fresh Windows Server 2022 VPS:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
# Fetch the bootstrap directly from the repo:
iwr 'https://raw.githubusercontent.com/<you>/<repo>/main/deploy/bootstrap-vps.ps1' -OutFile "$env:TEMP\bootstrap.ps1"
& "$env:TEMP\bootstrap.ps1" -Domain 'yourdomain.com' -RepoUrl 'https://github.com/<you>/<repo>.git'
```
What it does (all idempotent):
1. Installs PowerShell 7, Git, Caddy (winget), NSSM (chocolatey).
2. Opens Windows firewall for 80 + 443.
3. `git clone` (or `git pull`) into `C:\apps\axmclub`.
4. Generates a 48-char `AURUM_ADMIN_KEY` if `-AdminKey` isn't supplied, and installs `server.ps1` as the `axmclub` service.
5. Rewrites `Caddyfile` with your real domain, installs Caddy as the `caddy` service.
6. Registers the nightly db.json backup via `schtasks`.
7. Prints the admin key + the DNS records you still need to set in Cloudflare.
### Manual step-by-step (if you'd rather not run the bootstrap)
1. `winget install Microsoft.PowerShell` and `winget install CaddyServer.Caddy`; install NSSM (`choco install nssm` or the zip from nssm.cc).
2. Copy the repo to `C:\apps\axmclub` and open ports 80 + 443 in the Windows firewall.
3. From an elevated PowerShell 7:
   ```powershell
   .\deploy\install-service.ps1 -InstallPath 'C:\apps\axmclub' -Port 8080 -AdminKey '<long-random-string>'
   ```
4. Edit `deploy/Caddyfile` to point at your real domain, drop it at `C:\Caddy\Caddyfile`, and run Caddy (or wrap it in its own NSSM service). Point DNS at the VPS; Caddy fetches the cert on first hit.
5. Register the nightly backup:
   ```powershell
   schtasks /Create /TN "AxMclub DB backup" /SC DAILY /ST 03:30 /RL HIGHEST /RU SYSTEM `
     /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\apps\axmclub\deploy\backup-db.ps1 -InstallPath C:\apps\axmclub -BackupDir D:\backups\axmclub"
   ```
### Hardening checklist
- Set `AURUM_ADMIN_KEY` to a 32+ char random string (the install script stores it in the service env, not in code).
- Keep `admin.html` + `/api/admin/*` behind an IP allow-list at the Caddy layer (see the commented `@admin` matcher in `deploy/Caddyfile`) or Cloudflare Access.
- Back up `data/db.json` to a different disk/UNC path than the one holding the app.
- Rate-limit `/api/*` at the proxy (Caddy `rate_limit` plugin or Cloudflare rule) — the PowerShell listener is single-threaded.
- Rotate the admin key periodically: `nssm set axmclub AppEnvironmentExtra 'AURUM_ADMIN_KEY=<new>'` then `Restart-Service axmclub`.
- When HTTPS is stable on the domain for a week or two, uncomment HSTS in the Caddyfile.
## Security notes
This is local-dev grade. For production you'd want HTTPS + `Secure` cookies,
`bcrypt`/`argon2` instead of raw SHA-256, CSRF tokens, rate limiting, and a
real database.
