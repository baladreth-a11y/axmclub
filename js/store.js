// Tiny reactive store. `set` accepts a patch object OR an updater fn.
export function createStore(initial) {
  let state = initial;
  const listeners = new Set();
  return {
    get() { return state; },
    set(patch) {
      state = typeof patch === 'function' ? patch(state) : { ...state, ...patch };
      for (const fn of listeners) fn(state);
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
  cam: { active: false, expiresAt: 0, remainingMs: 0 }
});
