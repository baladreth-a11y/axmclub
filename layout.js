// Always-on Feedback & Ideas widget. Mounted into the bottom-right of
// every page by initSharedLayout(). Anonymous-friendly: anyone can drop
// a bug report or idea without signing in. Submissions are stored in
// db.feedback by the backend and surfaced in the admin panel.
import { api } from './api.js';
import { toast } from './ui.js';

const FAB_HTML = `
  <button id="feedbackFab" class="feedback-fab" type="button" aria-haspopup="dialog" aria-controls="feedbackModal" title="Send feedback or an idea">
    <span class="feedback-fab-icon" aria-hidden="true">💬</span>
    <span class="feedback-fab-label">Feedback</span>
  </button>
  <div id="feedbackBackdrop" class="feedback-backdrop hidden" role="dialog" aria-modal="true" aria-labelledby="feedbackTitle">
    <div id="feedbackModal" class="feedback-modal">
      <button type="button" class="feedback-modal-close" id="feedbackClose" aria-label="Close feedback">×</button>
      <h3 id="feedbackTitle">Feedback &amp; ideas</h3>
      <p class="muted">Spotted a bug, or have a feature idea? Tell us. Anonymous is fine.</p>
      <form id="feedbackForm" class="feedback-form">
        <fieldset class="feedback-types">
          <legend class="sr-only">Type</legend>
          <label class="feedback-type">
            <input type="radio" name="type" value="idea" checked />
            <span>💡 Idea</span>
          </label>
          <label class="feedback-type">
            <input type="radio" name="type" value="bug" />
            <span>🐞 Bug</span>
          </label>
          <label class="feedback-type">
            <input type="radio" name="type" value="other" />
            <span>✉️ Other</span>
          </label>
        </fieldset>
        <label class="feedback-field">
          <span>Message</span>
          <textarea name="message" rows="5" required minlength="2" maxlength="2000" placeholder="What happened, or what would you like to see?"></textarea>
        </label>
        <label class="feedback-field">
          <span>Contact <small class="muted">(optional)</small></span>
          <input name="contact" type="text" maxlength="200" placeholder="Email or handle if you want a reply" />
        </label>
        <div class="feedback-actions">
          <button type="button" class="btn btn-ghost" id="feedbackCancel">Cancel</button>
          <button type="submit" class="btn btn-primary">Send</button>
        </div>
        <p class="fine-print">We log the page URL so we can reproduce issues. No tracking pixels, no cookies on this submit.</p>
      </form>
    </div>
  </div>`;

function open() {
  document.getElementById('feedbackBackdrop')?.classList.remove('hidden');
  // Focus the textarea after the panel becomes visible.
  requestAnimationFrame(() => {
    document.querySelector('#feedbackForm textarea[name="message"]')?.focus();
  });
}

function close() {
  document.getElementById('feedbackBackdrop')?.classList.add('hidden');
}

async function onSubmit(e) {
  e.preventDefault();
  const form = e.currentTarget;
  const fd = new FormData(form);
  const payload = {
    type: (fd.get('type') || 'other').toString(),
    message: (fd.get('message') || '').toString().trim(),
    contact: (fd.get('contact') || '').toString().trim(),
    page: location.pathname + (location.search || '')
  };
  if (!payload.message) {
    toast('Please write something first.', 'error');
    return;
  }
  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;
  try {
    await api.submitFeedback(payload);
    toast('Thanks — your note is on the way.', 'success');
    form.reset();
    close();
  } catch (err) {
    toast(err.message || 'Could not send feedback.', 'error');
  } finally {
    if (submitBtn) submitBtn.disabled = false;
  }
}

export function initFeedback() {
  if (document.getElementById('feedbackFab')) return; // already mounted
  const host = document.createElement('div');
  host.id = 'feedbackHost';
  host.innerHTML = FAB_HTML;
  document.body.appendChild(host);

  document.getElementById('feedbackFab').addEventListener('click', open);
  document.getElementById('feedbackClose').addEventListener('click', close);
  document.getElementById('feedbackCancel').addEventListener('click', close);
  document.getElementById('feedbackBackdrop').addEventListener('click', e => {
    if (e.target.id === 'feedbackBackdrop') close();
  });
  document.getElementById('feedbackForm').addEventListener('submit', onSubmit);
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && !document.getElementById('feedbackBackdrop').classList.contains('hidden')) {
      close();
    }
  });
}
