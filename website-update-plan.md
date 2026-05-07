# Website Update Plan

## Goal

Stabilize the current AxMclub.com site, repair the public pages that were overwritten, and ship a small visible improvement without changing the core backend flow.

## Immediate Fixes

1. Restore broken public files.
   - `styles.css` must contain the main stylesheet, not page HTML.
   - `play.html` must contain the daily tasks and roulette page.
   - `model.html` must contain the model dashboard page.
   - `README.md` must contain project setup notes, not ignore patterns.

2. Audit duplicate root and `js/` files.
   - The active pages import from `./js/...`, so the `js/` directory should be the source of truth.
   - Root-level duplicate JavaScript files should either be removed from deploy paths or regenerated intentionally to avoid accidental stale code.

3. Keep maintenance mode intentional.
   - `index.html` has been restored to the full homepage from the packaged project.
   - Use `maintenance.html` plus the maintenance deploy scripts when the site needs to go offline.

4. Verify the age gate and auth flow.
   - Anonymous visitor sees the age gate.
   - After age confirmation, player/model browsing is visible as intended.
   - Login/register modals open and close without JavaScript errors.

## Small Website Change

Add a cleaner "Latest updates" strip to the homepage or main member page after the site is out of maintenance. Suggested content:

- Daily spin rewards refreshed.
- Model dashboard gallery and password tools available.
- Feedback and ideas button now available site-wide.

This gives visitors a clear signal that the site is active without turning the page into a marketing landing page.

## Next Improvements

1. Mobile navigation polish.
   - Test the nav toggle at phone widths.
   - Check that communicator, feedback, toast, and modals do not overlap.

2. Accessibility cleanup.
   - Replace symbolic sign-out text with a clearer icon or label.
   - Confirm focus handling for modals and the age gate.
   - Add missing button disabled/loading states for async actions.

3. Error-state consistency.
   - Standardize "could not load" messages across models, tasks, rewards, admin, and communicator.
   - Keep user-facing errors short and log technical details to the console/server.

4. Deployment hygiene.
   - Make sure `data/`, `uploads/`, logs, PID files, and zip artifacts are ignored or excluded from production deploys.
   - Keep deployment scripts in `deploy/` as the canonical copy.

## Verification Checklist

Run these before publishing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\e2e-test.ps1
```

Then manually check:

- `/`
- `/players.html`
- `/play.html`
- `/model.html`
- `/cam.html`
- `/marketplace.html`
- `/supporters.html`
- `/admin.html`
