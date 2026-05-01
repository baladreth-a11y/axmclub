// Cam2cam WebRTC helper. Talks to the short-polled signalling endpoints
// in Handle-Cam (request / inbox / respond / signal / end) and pipes
// SDP + ICE through them. STUN-only — TURN fallback is deferred. The
// browser is the source of truth for media; the server only relays
// signalling payloads. Exposes a few imperative entry points used by
// camroom.js plus a getCallState() snapshot for UI rendering.
import { api } from './api.js';
import { store } from './store.js';

// Public Google STUN. We deliberately don't ship TURN here — adding one
// is a single push to AURUM_TURN_* env vars later.
const ICE_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }];

const POLL_SETUP_MS  = 1500;
const POLL_LIVE_MS   = 5000;

let pc = null;            // RTCPeerConnection
let localStream = null;   // MediaStream from getUserMedia
let signalTimer = null;
let lastSignalSeq = 0;
let currentCallId = '';
let currentRole = '';     // 'caller' | 'callee'
let currentPeerEmail = '';
let currentPeerName = '';
let isRemoteDescriptionSet = false;
let pendingRemoteIce = [];

const listeners = new Set();

function setCallState(patch) {
  const cur = store.get().cam.call || {};
  const next = { ...cur, ...patch };
  store.set(s => ({ ...s, cam: { ...s.cam, call: next } }));
  for (const fn of listeners) {
    try { fn(next); } catch (err) { console.error('[axm/cam] listener failed:', err); }
  }
}

export function onCallStateChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function getCallState() {
  return (store.get().cam.call) || { status: 'idle' };
}

function tearDownPeer() {
  if (signalTimer) { clearInterval(signalTimer); signalTimer = null; }
  if (pc) {
    try { pc.onicecandidate = null; pc.ontrack = null; pc.onconnectionstatechange = null; } catch {}
    try { pc.close(); } catch {}
    pc = null;
  }
  if (localStream) {
    for (const t of localStream.getTracks()) {
      try { t.stop(); } catch {}
    }
    localStream = null;
  }
  isRemoteDescriptionSet = false;
  pendingRemoteIce = [];
  lastSignalSeq = 0;
}

async function ensureLocalStream() {
  if (localStream) return localStream;
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    throw new Error('Camera/mic API is not available in this browser.');
  }
  localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
  return localStream;
}

function attachLocalStream(stream) {
  const localEl = document.getElementById('camLocal');
  if (localEl) {
    localEl.srcObject = stream;
    localEl.muted = true;
    localEl.play && localEl.play().catch(() => {});
  }
}

function attachRemoteStream(stream) {
  const remoteEl = document.getElementById('camRemote');
  if (remoteEl) {
    remoteEl.srcObject = stream;
    remoteEl.play && remoteEl.play().catch(() => {});
  }
}

function buildPeerConnection() {
  const conn = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  conn.onicecandidate = e => {
    if (!e.candidate || !currentCallId) return;
    api.camSignal(currentCallId, 'ice', e.candidate.toJSON()).catch(err => {
      console.error('[axm/cam] ICE send failed:', err);
    });
  };
  conn.ontrack = e => {
    const [stream] = e.streams;
    if (stream) attachRemoteStream(stream);
  };
  conn.onconnectionstatechange = () => {
    const st = conn.connectionState;
    if (st === 'connected') {
      setCallState({ status: 'live', startedAt: getCallState().startedAt || Date.now() });
      if (signalTimer) { clearInterval(signalTimer); signalTimer = setInterval(pollSignals, POLL_LIVE_MS); }
    } else if (st === 'failed' || st === 'disconnected' || st === 'closed') {
      if (st === 'failed') setCallState({ status: 'failed', error: 'Connection failed.' });
    }
  };
  return conn;
}

async function applyIncomingSignal(sig) {
  if (!pc) return;
  if (sig.kind === 'offer') {
    await pc.setRemoteDescription(new RTCSessionDescription(sig.payload));
    isRemoteDescriptionSet = true;
    for (const cand of pendingRemoteIce) {
      try { await pc.addIceCandidate(new RTCIceCandidate(cand)); } catch (err) { console.error('[axm/cam] queued ICE failed:', err); }
    }
    pendingRemoteIce = [];
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await api.camSignal(currentCallId, 'answer', answer);
  } else if (sig.kind === 'answer') {
    await pc.setRemoteDescription(new RTCSessionDescription(sig.payload));
    isRemoteDescriptionSet = true;
    for (const cand of pendingRemoteIce) {
      try { await pc.addIceCandidate(new RTCIceCandidate(cand)); } catch (err) { console.error('[axm/cam] queued ICE failed:', err); }
    }
    pendingRemoteIce = [];
  } else if (sig.kind === 'ice') {
    if (!sig.payload) return;
    if (!isRemoteDescriptionSet) {
      pendingRemoteIce.push(sig.payload);
      return;
    }
    try { await pc.addIceCandidate(new RTCIceCandidate(sig.payload)); }
    catch (err) { console.error('[axm/cam] addIceCandidate failed:', err); }
  } else if (sig.kind === 'bye') {
    setCallState({ status: 'ended' });
    tearDownPeer();
  }
}

async function pollSignals() {
  if (!currentCallId) return;
  try {
    const res = await api.camSignalGet(currentCallId, lastSignalSeq);
    if (res.status === 'ended' || res.status === 'declined') {
      setCallState({ status: 'ended' });
      tearDownPeer();
      return;
    }
    for (const sig of res.signals || []) {
      if (sig.seq <= lastSignalSeq) continue;
      lastSignalSeq = sig.seq;
      try { await applyIncomingSignal(sig); }
      catch (err) { console.error('[axm/cam] applyIncomingSignal failed:', err); }
    }
  } catch (err) {
    if (err.status === 404) {
      setCallState({ status: 'ended', error: 'Call expired.' });
      tearDownPeer();
    } else {
      console.error('[axm/cam] signal poll failed:', err);
    }
  }
}

function startSignalTimer() {
  if (signalTimer) clearInterval(signalTimer);
  signalTimer = setInterval(pollSignals, POLL_SETUP_MS);
}

// Caller flow: send /request, wait for the callee to accept (the camroom
// inbox poller calls openCallerOnAccept once the inbox shows status =
// 'accepted'), then start media + offer.
export async function startCall(peerEmail, peerName) {
  if (currentCallId) await endCall();
  setCallState({ status: 'requesting', peerEmail, peerName: peerName || peerEmail, error: '' });
  try {
    const res = await api.camRequest(peerEmail);
    currentCallId = res.id;
    currentRole = 'caller';
    currentPeerEmail = peerEmail;
    currentPeerName = peerName || peerEmail;
    setCallState({ id: res.id, status: 'requesting', peerEmail, peerName: peerName || peerEmail });
    return res;
  } catch (err) {
    setCallState({ status: 'failed', error: err.message || 'Request failed.' });
    throw err;
  }
}

// Caller side: triggered by camroom.js when the inbox poller sees
// status = 'accepted' on a call we initiated. Spins up the local stream
// + RTCPeerConnection and sends the SDP offer.
export async function openCallerOnAccept(callId, peerEmail, peerName) {
  if (callId !== currentCallId) currentCallId = callId;
  currentRole = 'caller';
  currentPeerEmail = peerEmail;
  currentPeerName = peerName;
  setCallState({ id: callId, status: 'connecting', peerEmail, peerName });
  try {
    const stream = await ensureLocalStream();
    attachLocalStream(stream);
    pc = buildPeerConnection();
    for (const t of stream.getTracks()) pc.addTrack(t, stream);
    const offer = await pc.createOffer({ offerToReceiveVideo: true, offerToReceiveAudio: true });
    await pc.setLocalDescription(offer);
    await api.camSignal(callId, 'offer', offer);
    startSignalTimer();
  } catch (err) {
    setCallState({ status: 'failed', error: err.message || 'Could not start media.' });
    tearDownPeer();
    try { await api.camEnd(callId); } catch {}
    throw err;
  }
}

// Callee flow: accept the request, capture media, open RTCPeerConnection,
// poll for the SDP offer, send the answer.
export async function acceptCall(callId, peerEmail, peerName) {
  if (currentCallId && currentCallId !== callId) await endCall();
  currentCallId = callId;
  currentRole = 'callee';
  currentPeerEmail = peerEmail;
  currentPeerName = peerName || peerEmail;
  setCallState({ id: callId, status: 'connecting', peerEmail, peerName: peerName || peerEmail, error: '' });
  try {
    await api.camRespond(callId, true);
    const stream = await ensureLocalStream();
    attachLocalStream(stream);
    pc = buildPeerConnection();
    for (const t of stream.getTracks()) pc.addTrack(t, stream);
    startSignalTimer();
  } catch (err) {
    setCallState({ status: 'failed', error: err.message || 'Could not accept call.' });
    tearDownPeer();
    try { await api.camEnd(callId); } catch {}
    throw err;
  }
}

export async function declineCall(callId) {
  try { await api.camRespond(callId, false); } catch {}
  if (callId === currentCallId) {
    setCallState({ status: 'ended' });
    tearDownPeer();
    currentCallId = '';
  }
}

export async function endCall() {
  const id = currentCallId;
  if (!id) {
    setCallState({ status: 'idle', id: '', error: '' });
    return;
  }
  try { await api.camSignal(id, 'bye', null); } catch {}
  try { await api.camEnd(id); } catch {}
  setCallState({ status: 'ended' });
  tearDownPeer();
  currentCallId = '';
  currentRole = '';
  // Reset back to idle on the next tick so the UI can show 'ended' briefly.
  setTimeout(() => setCallState({ status: 'idle', id: '', peerEmail: '', peerName: '', error: '' }), 600);
}

export function toggleMicMuted() {
  if (!localStream) return false;
  const tracks = localStream.getAudioTracks();
  if (!tracks.length) return false;
  const enabled = !tracks[0].enabled;
  for (const t of tracks) t.enabled = enabled;
  return !enabled;  // returns true when muted
}

export function toggleVideoMuted() {
  if (!localStream) return false;
  const tracks = localStream.getVideoTracks();
  if (!tracks.length) return false;
  const enabled = !tracks[0].enabled;
  for (const t of tracks) t.enabled = enabled;
  return !enabled;
}

export function isMicMuted() {
  if (!localStream) return false;
  const tracks = localStream.getAudioTracks();
  return tracks.length > 0 && !tracks[0].enabled;
}

export function isVideoMuted() {
  if (!localStream) return false;
  const tracks = localStream.getVideoTracks();
  return tracks.length > 0 && !tracks[0].enabled;
}
