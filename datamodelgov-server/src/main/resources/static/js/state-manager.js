/**
 * Local State Manager for C-end Experience
 * Provides centralized state management with local persistence
 */

class StateManager {
    constructor() {
        this.state = {};
        this.listeners = {};
        this.persistKeys = new Set();
    }

    /**
     * Initialize state manager with persisted values
     */
    async init() {
        if (window.localDB) {
            try {
                const persistedState = await window.localDB.get('metadata', 'app_state');
                if (persistedState && persistedState.value) {
                    this.state = { ...this.state, ...persistedState.value };
                    console.log('State manager initialized with persisted state');
                }
            } catch (error) {
                console.error('Failed to load persisted state:', error);
            }
        }
    }

    /**
     * Get state value
     */
    get(key) {
        return this.state[key];
    }

    /**
     * Set state value
     */
    set(key, value, persist = false) {
        const oldValue = this.state[key];
        this.state[key] = value;

        if (persist) {
            this.persistKeys.add(key);
            this.persistState();
        }

        // Notify listeners
        if (this.listeners[key]) {
            this.listeners[key].forEach(callback => {
                callback(value, oldValue);
            });
        }
    }

    /**
     * Update state with partial object
     */
    update(updates, persist = false) {
        Object.keys(updates).forEach(key => {
            const oldValue = this.state[key];
            this.state[key] = updates[key];

            if (persist) {
                this.persistKeys.add(key);
            }

            // Notify listeners
            if (this.listeners[key]) {
                this.listeners[key].forEach(callback => {
                    callback(updates[key], oldValue);
                });
            }
        });

        if (persist) {
            this.persistState();
        }
    }

    /**
     * Subscribe to state changes
     */
    subscribe(key, callback) {
        if (!this.listeners[key]) {
            this.listeners[key] = [];
        }
        this.listeners[key].push(callback);

        // Return unsubscribe function
        return () => {
            this.listeners[key] = this.listeners[key].filter(cb => cb !== callback);
        };
    }

    /**
     * Persist state to IndexedDB
     */
    async persistState() {
        if (!window.localDB) return;

        try {
            const persistedState = {};
            this.persistKeys.forEach(key => {
                persistedState[key] = this.state[key];
            });

            await window.localDB.setCacheMetadata('app_state', {
                value: persistedState
            });
        } catch (error) {
            console.error('Failed to persist state:', error);
        }
    }

    /**
     * Clear all state
     */
    clear() {
        this.state = {};
        this.persistKeys.clear();
        this.persistState();
    }

    /**
     * Get all state
     */
    getAll() {
        return { ...this.state };
    }
}

// Global instance
const stateManager = new StateManager();

// Auto-initialize on load
if (typeof window !== 'undefined') {
    window.stateManager = stateManager;
    stateManager.init().catch(console.error);
}
