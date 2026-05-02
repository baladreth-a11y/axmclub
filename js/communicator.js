// Communicator: floating bottom-left bubble + dock panel that hosts a
// presence list (Online tab) and existing thread list (Threads tab).
// Selecting a peer opens a chat view that polls /api/chat/messages every
// 3 s while open. While the panel is closed, /api/chat/threads is polled
// every 8 s for unread counts. Mounted on every page by initSharedLayout.
import { api } from './api.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { startCall } from './camCall.js';

const POLL_THREADS_MS  = 8000;
const POLL_MESSAGES_MS = 3000;
const POLL_ONLINE_MS   = 5000;

let panelOpen     = false;
let activeTab     = 'online';   // 'online' | 'threads' | 'room'
let openWith      = '';         // peer email currently shown in the chat view
let lastSince     = 0;          // last message timestamp we've fetched
let roomSince     = 0;          // last public room message timestamp fetched
let messagesCache = [];
let roomMessagesCache = [];
let threadsTimer  = null;
let messagesTimer = null;
let roomTimer     = null;
let onlineTimer   = null;
let peerCam2cam   = false;
let myCam2cam     = false;

const FAB_HTML = `
  <button id="commFab" class="comm-fab" type="button" aria-haspopup="dialog" aria-controls="commPanel" title="Open chat">
    <span class="comm-fab-icon" aria-hidden="true">\u{1F4AC}</span>
    <span class="comm-fab-label">Chat</span>
    <span id="commUnreadBadge" class="comm-unread hidden">0</span>
  </button>
  <div id="commPanel" class="comm-panel hidden" role="dialog" aria-modal="false" aria-labelledby="commPanelTitle">
    <header class="comm-panel-head">
      <h3 id="commPanelTitle" class="comm-panel-title">Communicator</h3>
      <button type="button" class="comm-panel-close" id="commPanelClose" aria-label="Close chat">\u00d7</button>
    </header>
    <div class="comm-tabs" role="tablist">
      <button class="comm-tab is-active" data-tab="online" role="tab" aria-selected="true">Online</button>
      <button class="comm-tab" data-tab="threads" role="tab" aria-selected="false">
        <span>Threads</span>
        <span id="commTabUnread" class="comm-tab-badge hidden">0</span>
      </button>
      <button class="comm-tab" data-tab="room" role="tab" aria-selected="false">Room</button>
    </div>
    <div class="comm-list-wrap">
      <ul id="commOnlineList" class="comm-list comm-list--online"></ul>
      <ul id="commThreadList" class="comm-list comm-list--threads hidden"></ul>
      <div id="commRoomView" class="comm-room hidden" aria-live="polite">
        <div class="comm-chat-head">
          <div></div>
          <div class="comm-chat-ident">
            <strong>Public room</strong>
            <span class="comm-peer-status"><span class="online-dot" data-online="true"></span> Everyone</span>
          </div>
          <div></div>
        </div>
        <div id="commRoomMessages" class="comm-messages"></div>
        <form id="commRoomComposeForm" class="comm-compose">
          <textarea id="commRoomComposeText" rows="2" maxlength="2000" placeholder="Say something to the room…"></textarea>
          <button type="submit" class="btn btn-primary comm-send">Send</button>
        </form>
      </div>
    </div>
    <div id="commChatView" class="comm-chat hidden" aria-live="polite">
      <div class="comm-chat-head">
        <button type="button" class="comm-back" id="commBack" aria-label="Back">\u2190</button>
        <div class="comm-chat-ident">
          <strong id="commPeerName">Peer</strong>
          <span id="commPeerStatus" class="comm-peer-status">
            <span class="online-dot" data-online="false"></span>
            <span id="commPeerStatusLabel">Offline</span>
          </span>
        </div>
        <button type="button" class="btn btn-outline comm-cam2cam hidden" id="commCam2cam" title="Send cam2cam request">
          \u{1F3A5} Cam2cam
        </button>
      </div>
      <div id="commMessages" class="comm-messages"></div>
      <form id="commComposeForm" class="comm-compose">
        <textarea id="commComposeText" rows="2" maxlength="2000" placeholder="Type a message\u2026"></textarea>
        <button type="submit" class="btn btn-primary comm-send">Send</button>
      </form>
    </div>
    <div id="commSignedOut" class="comm-empty hidden">
      Sign in to chat with members.
    </div>
  </div>`;

function $(s) { return document.querySelector(s); }
function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}
function formatTime(ms) {
  if (!ms) return '';
  const d = new Date(ms);
  if (isNaN(d.getTime())) return '';
  return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}

function renderUnreadBadge(unread) {
  const fabBadge = $('#commUnreadBadge');
  const tabBadge = $('#commTabUnread');
  if (fabBadge) {
    fabBadge.textContent = unread > 99 ? '99+' : String(unread);
    fabBadge.classList.toggle('hidden', !unread);
  }
  if (tabBadge) {
    tabBadge.textContent = unread > 99 ? '99+' : String(unread);
    tabBadge.classList.toggle('hidden', !unread);
  }
}

function renderOnline(list) {
  const ul = $('#commOnlineList');
  if (!ul) return;
  if (!list || !list.length) {
    ul.innerHTML = '<li class="comm-empty">No one else online right now.</li>';
    return;
  }
  ul.innerHTML = list.map(u => `
    <li class="comm-item" data-peer="${escapeHtml(u.email)}">
      <span class="online-dot" data-online="true"></span>
      <div class="comm-item-main">
        <strong>${escapeHtml(u.name || u.email)}</strong>
        <small class="muted">${escapeHtml(u.isModel ? 'Model' : 'Supporter')}</small>
      </div>
      <button type="button" class="btn btn-outline comm-open-btn" data-peer="${escapeHtml(u.email)}" data-name="${escapeHtml(u.name || u.email)}">
        Chat
      </button>
    </li>`).join('');
}

function renderThreads(list) {
  const ul = $('#commThreadList');
  if (!ul) return;
  if (!list || !list.length) {
    ul.innerHTML = '<li class="comm-empty">No conversations yet. Start one from the Online tab.</li>';
    return;
  }
  ul.innerHTML = list.map(t => `
    <li class="comm-item${t.unread ? ' has-unread' : ''}" data-peer="${escapeHtml(t.peerEmail)}">
      <span class="online-dot" data-online="${t.peerOnline ? 'true' : 'false'}"></span>
      <div class="comm-item-main">
        <strong>${escapeHtml(t.peerName || t.peerEmail)}</strong>
        <small class="muted comm-last">${escapeHtml(t.lastMessage || 'No messages yet.')}</small>
      </div>
      <span class="comm-item-meta">
        ${t.unread ? `<span class="comm-tab-badge">${t.unread > 99 ? '99+' : t.unread}</span>` : ''}
      </span>
    </li>`).join('');
}

function renderMessages() {
  const wrap = $('#commMessages');
  if (!wrap) return;
  const myEmail = ((store.get().user || {}).email || '').toLowerCase();
  if (!messagesCache.length) {
    wrap.innerHTML = '<div class="comm-empty">No messages yet. Say hi!</div>';
    return;
  }
  wrap.innerHTML = messagesCache.map(m => {
    const mine = (m.from || '').toLowerCase() === myEmail;
    return `
      <div class="comm-msg ${mine ? 'is-mine' : 'is-peer'}">
        <div class="comm-msg-bubble">${escapeHtml(m.text)}</div>
        <div class="comm-msg-time muted">${escapeHtml(formatTime(m.at))}</div>
      </div>`;
  }).join('');
  // Scroll to the latest message.
  wrap.scrollTop = wrap.scrollHeight;
}

function renderRoomMessages() {
  const wrap = $('#commRoomMessages');
  if (!wrap) return;
  if (!roomMessagesCache.length) {
    wrap.innerHTML = '<div class="comm-empty">No messages yet. Be the first to say hi.</div>';
    return;
  }
  wrap.innerHTML = roomMessagesCache.map(m => {
    const mine = (m.from || '').toLowerCase() === ((store.get().user || {}).email || '').toLowerCase();
    return `
      <div class="comm-msg ${mine ? 'is-mine' : 'is-peer'}">
        <div class="comm-msg-bubble"><strong>${escapeHtml(m.name)}:</strong> ${escapeHtml(m.text)}</div>
        <div class="comm-msg-time muted">${escapeHtml(formatTime(m.at))}</div>
      </div>`;
  }).join('');
  wrap.scrollTop = wrap.scrollHeight;
}

function renderPeerHeader(name, online, peerCam) {
  const nameEl = $('#commPeerName');
  if (nameEl) nameEl.textContent = name || '\u2014';
  const dot = document.querySelector('#commPeerStatus .online-dot');
  if (dot) dot.dataset.online = online ? 'true' : 'false';
  const lbl = $('#commPeerStatusLabel');
  if (lbl) lbl.textContent = online ? 'Online' : 'Offline';
  const camBtn = $('#commCam2cam');
  if (camBtn) {
    camBtn.classList.toggle('hidden', !(peerCam && myCam2cam));
  }
}

function showChatView(peerEmail, peerName) {
  openWith = peerEmail;
  lastSince = 0;
  messagesCache = [];
  $('#commOnlineList').classList.add('hidden');
  $('#commThreadList').classList.add('hidden');
  $('#commChatView').classList.remove('hidden');
  document.querySelectorAll('.comm-tab').forEach(t => t.classList.add('is-disabled'));
  renderPeerHeader(peerName || peerEmail, false, false);
  $('#commMessages').innerHTML = '<div class="comm-empty">Loading\u2026</div>';
  store.set(s => ({ ...s, chat: { ...s.chat, openWith: peerEmail, messages: [] } }));
  fetchMessages(true);
  startMessagesTimer();
}

function backToList() {
  openWith = '';
  $('#commChatView').classList.add('hidden');
  document.querySelectorAll('.comm-tab').forEach(t => t.classList.remove('is-disabled'));
  $('#commOnlineList').classList.add('hidden');
  $('#commThreadList').classList.add('hidden');
  $('#commRoomView').classList.add('hidden');
  if (activeTab === 'online') {
    $('#commOnlineList').classList.remove('hidden');
  } else if (activeTab === 'threads') {
    $('#commThreadList').classList.remove('hidden');
  } else if (activeTab === 'room') {
    $('#commRoomView').classList.remove('hidden');
  }
  store.set(s => ({ ...s, chat: { ...s.chat, openWith: '', messages: [] } }));
  stopMessagesTimer();
  stopRoomTimer();
  // Pull fresh thread state so unread badges update.
  fetchThreads();
}

function setActiveTab(tab) {
  activeTab = tab;
  document.querySelectorAll('.comm-tab').forEach(btn => {
    const on = btn.dataset.tab === tab;
    btn.classList.toggle('is-active', on);
    btn.setAttribute('aria-selected', on ? 'true' : 'false');
  });
  if (openWith) return;
  $('#commOnlineList').classList.toggle('hidden', tab !== 'online');
  $('#commThreadList').classList.toggle('hidden', tab !== 'threads');
  $('#commRoomView').classList.toggle('hidden', tab !== 'room');
  if (tab === 'online') fetchOnline();
  if (tab === 'threads') fetchThreads();
  if (tab === 'room') fetchRoomMessages(true);
}

async function fetchOnline() {
  try {
    const { users } = await api.online();
    store.set(s => ({ ...s, online: users || [] }));
    renderOnline(users || []);
  } catch (err) {
    if (err.status === 401) renderOnline([]);
  }
}

async function fetchThreads() {
  try {
    const { threads, unread } = await api.chatThreads();
    store.set(s => ({ ...s, chat: { ...s.chat, threads: threads || [], unread: unread | 0 } }));
    renderThreads(threads || []);
    renderUnreadBadge(unread | 0);
  } catch (err) {
    if (err.status === 401) {
      renderThreads([]);
      renderUnreadBadge(0);
    }
  }
}

async function fetchMessages(initial) {
  if (!openWith) return;
  try {
    const res = await api.chatMessages(openWith, lastSince || 0);
    if (res.peerName) renderPeerHeader(res.peerName, !!res.peerOnline, !!res.peerCam2cam);
    peerCam2cam = !!res.peerCam2cam;
    myCam2cam = !!res.myCam2cam;
    const incoming = res.messages || [];
    if (incoming.length) {
      // Merge by id (in case of retries) and re-sort by time.
      const byId = new Map(messagesCache.map(m => [m.id, m]));
      for (const m of incoming) byId.set(m.id, m);
      messagesCache = Array.from(byId.values()).sort((a, b) => a.at - b.at);
      lastSince = messagesCache[messagesCache.length - 1].at;
      store.set(s => ({ ...s, chat: { ...s.chat, messages: messagesCache.slice() } }));
      renderMessages();
    } else if (initial) {
      renderMessages();
    }
    // Reading messages clears unread for the open peer.
    fetchThreads();
  } catch (err) {
    if (err.status === 401) {
      stopMessagesTimer();
      backToList();
    }
  }
}

async function fetchRoomMessages(initial) {
  try {
    const res = await api.chatPublicMessages(roomSince || 0);
    const incoming = res.messages || [];
    if (incoming.length) {
      const byId = new Map(roomMessagesCache.map(m => [m.id, m]));
      for (const m of incoming) byId.set(m.id, m);
      roomMessagesCache = Array.from(byId.values()).sort((a, b) => a.at - b.at);
      roomSince = roomMessagesCache[roomMessagesCache.length - 1].at;
      renderRoomMessages();
    } else if (initial) {
      renderRoomMessages();
    }
  } catch (err) {
    if (err.status === 401) {
      $('#commRoomMessages').innerHTML = '<div class="comm-empty">Sign in to join the room.</div>';
    }
  }
}

async function onSend(e) {
  e.preventDefault();
  if (!openWith) return;
  const ta = $('#commComposeText');
  const text = (ta.value || '').trim();
  if (!text) return;
  ta.disabled = true;
  try {
    const res = await api.chatSend(openWith, text);
    ta.value = '';
    if (res && res.message) {
      messagesCache.push(res.message);
      lastSince = Math.max(lastSince, res.message.at | 0);
      renderMessages();
    }
    fetchThreads();
  } catch (err) {
    toast(err.message || 'Could not send message.', 'error');
  } finally {
    ta.disabled = false;
    ta.focus();
  }
}

function onComposeKey(e) {
  // Enter sends, Shift+Enter inserts newline.
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    $('#commComposeForm').requestSubmit();
  }
}

function startThreadsTimer() {
  stopThreadsTimer();
  threadsTimer = setInterval(fetchThreads, POLL_THREADS_MS);
}
function stopThreadsTimer() { if (threadsTimer) { clearInterval(threadsTimer); threadsTimer = null; } }
function startMessagesTimer() {
  stopMessagesTimer();
  messagesTimer = setInterval(() => fetchMessages(false), POLL_MESSAGES_MS);
}
function stopMessagesTimer() { if (messagesTimer) { clearInterval(messagesTimer); messagesTimer = null; } }
function startRoomTimer() {
  stopRoomTimer();
  roomTimer = setInterval(() => { if (panelOpen && activeTab === 'room' && !openWith) fetchRoomMessages(false); }, POLL_MESSAGES_MS);
}
function stopRoomTimer() { if (roomTimer) { clearInterval(roomTimer); roomTimer = null; } }
function startOnlineTimer() {
  stopOnlineTimer();
  onlineTimer = setInterval(() => { if (panelOpen && activeTab === 'online' && !openWith) fetchOnline(); }, POLL_ONLINE_MS);
}
function stopOnlineTimer() { if (onlineTimer) { clearInterval(onlineTimer); onlineTimer = null; } }

function refreshForUser(user) {
  if (!user) {
    // Anonymous: hide signed-in views, show prompt.
    $('#commOnlineList').classList.add('hidden');
    $('#commThreadList').classList.add('hidden');
    $('#commRoomView').classList.add('hidden');
    $('#commChatView').classList.add('hidden');
    $('#commSignedOut').classList.remove('hidden');
    renderUnreadBadge(0);
    stopThreadsTimer();
    stopMessagesTimer();
    stopRoomTimer();
    stopOnlineTimer();
    return;
  }
  $('#commSignedOut').classList.add('hidden');
  if (openWith) {
    $('#commChatView').classList.remove('hidden');
  } else {
    setActiveTab(activeTab);
  }
  startThreadsTimer();
  startOnlineTimer();
  if (activeTab === 'room') {
    fetchRoomMessages(true);
    startRoomTimer();
  }
  fetchThreads();
  if (activeTab === 'online' && !openWith) fetchOnline();
  myCam2cam = !!user.cam2cam;
}

function openPanel() {
  panelOpen = true;
  $('#commPanel').classList.remove('hidden');
  $('#commFab').classList.add('is-open');
  refreshForUser(store.get().user);
}

function closePanel() {
  panelOpen = false;
  $('#commPanel').classList.add('hidden');
  $('#commFab').classList.remove('is-open');
  stopMessagesTimer();
  stopOnlineTimer();
  // keep the threads timer running so the unread badge stays current.
}

// Programmatic entry point: open the panel and pre-load `peerEmail`.
// Used by the cam room's side-chat helper button.
export function openCommunicatorWith(peerEmail, peerName) {
  const fab = document.getElementById('commFab');
  if (!fab) return;
  if (!panelOpen) fab.click();
  if (peerEmail) showChatView(peerEmail, peerName || peerEmail);
}

export function initCommunicator() {
  if (document.getElementById('commFab')) return;
  const host = document.createElement('div');
  host.id = 'commHost';
  host.innerHTML = FAB_HTML;
  document.body.appendChild(host);

  $('#commFab').addEventListener('click', () => (panelOpen ? closePanel() : openPanel()));
  $('#commPanelClose').addEventListener('click', closePanel);
  $('#commBack').addEventListener('click', backToList);

  document.querySelectorAll('.comm-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      if (btn.classList.contains('is-disabled')) return;
      setActiveTab(btn.dataset.tab);
    });
  });

  // Delegated: clicking an online row or the Chat button opens that peer.
  $('#commOnlineList').addEventListener('click', e => {
    const btn = e.target.closest('.comm-open-btn') || e.target.closest('.comm-item');
    if (!btn) return;
    const peer = btn.dataset.peer;
    const name = btn.dataset.name || (btn.querySelector('strong') && btn.querySelector('strong').textContent) || peer;
    if (peer) showChatView(peer, name);
  });
  $('#commThreadList').addEventListener('click', e => {
    const item = e.target.closest('.comm-item');
    if (!item) return;
    const peer = item.dataset.peer;
    const name = (item.querySelector('strong') && item.querySelector('strong').textContent) || peer;
    if (peer) showChatView(peer, name);
  });

  $('#commComposeForm').addEventListener('submit', onSend);
  $('#commComposeText').addEventListener('keydown', onComposeKey);
  $('#commRoomComposeForm').addEventListener('submit', async e => {
    e.preventDefault();
    const ta = $('#commRoomComposeText');
    if (!ta) return;
    const text = (ta.value || '').trim();
    if (!text) return;
    ta.disabled = true;
    try {
      await api.chatPublicSend(text);
      ta.value = '';
      fetchRoomMessages(true);
    } catch (err) {
      toast(err.message || 'Could not send room message.', 'error');
    } finally {
      ta.disabled = false;
      ta.focus();
    }
  });

  $('#commCam2cam').addEventListener('click', async () => {
    if (!openWith) return;
    const me = store.get().user;
    if (!me)             { toast('Sign in first.', 'info'); return; }
    if (!me.cam2cam)     { toast('Turn on cam2cam from the cam room first.', 'info'); return; }
    if (!peerCam2cam)    { toast('Peer hasn\u2019t enabled cam2cam.', 'info'); return; }
    try {
      const peerName = $('#commPeerName')?.textContent || openWith;
      await startCall(openWith, peerName);
      toast(`Cam2cam request sent to ${peerName}. Open the cam room to continue.`);
      // If we're not on the cam page, send the user there.
      if (!/cam\.html$/i.test(location.pathname)) {
        setTimeout(() => { location.href = '/cam.html'; }, 600);
      }
    } catch (err) {
      if (err.status === 403 && err.data && err.data.reason === 'cam2cam-off') {
        toast('Both sides need cam2cam enabled.', 'info');
      } else {
        toast(err.message || 'Could not send cam2cam request.', 'error');
      }
    }
  });

  // React to user state changes.
  refreshForUser(store.get().user);
  store.subscribe(state => {
    if (panelOpen) refreshForUser(state.user);
    else if (state.user) {
      // Keep unread badge fresh while panel is closed.
      if (!threadsTimer) {
        startThreadsTimer();
        fetchThreads();
      }
    } else {
      renderUnreadBadge(0);
      stopThreadsTimer();
    }
  });
}
