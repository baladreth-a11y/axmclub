// Tiny reactive store. `set` accepts a patch object OR an updater fn.
// Subscribers are isolated: if one throws, the others still run, and the
// error is logged with an [axm] prefix so it shows up in the global error
// boundary's console output without breaking the caller (e.g. auth.js's
// closeModal after register).
export function createStore(initial) {
  let state = initial;
  const listeners = new Set();
  return {
    get() { return state; },
    set(patch) {
      state = typeof patch === 'function' ? patch(state) : { ...state, ...patch };
      for (const fn of listeners) {
        try { fn(state); }
        catch (err) { console.error('[axm] store subscriber failed:', err); }
      }
    },
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); }
  };
}

// Shared app state. Modules subscribe to react.
export const store = createStore({
  user: null,
  stats: { members: 0, spins: 0 },
  leaderboard: [],
  rewards: [],
  tasks: [],
  cam: { active: false, expiresAt: 0, remainingMs: 0 },
  // Communicator: presence + 1:1 chat panel state.
  online: [],
  chat: { threads: [], openWith: '', messages: [], unread: 0, peerOnline: false, peerCam2cam: false }
});
