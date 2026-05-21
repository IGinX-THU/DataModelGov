/**
 * Local Database Wrapper using IndexedDB
 * Provides offline data persistence for C-end experience
 */

class LocalDB {
    constructor(dbName = 'DataModelGovDB', version = 1) {
        this.dbName = dbName;
        this.version = version;
        this.db = null;
    }

    async init() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open(this.dbName, this.version);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                this.db = request.result;
                resolve(this.db);
            };

            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                
                // Projects store
                if (!db.objectStoreNames.contains('projects')) {
                    const projectStore = db.createObjectStore('projects', { keyPath: 'id' });
                    projectStore.createIndex('name', 'name', { unique: false });
                    projectStore.createIndex('type', 'type', { unique: false });
                    projectStore.createIndex('createTime', 'createTime', { unique: false });
                }

                // Algorithms store
                if (!db.objectStoreNames.contains('algorithms')) {
                    const algoStore = db.createObjectStore('algorithms', { keyPath: 'id' });
                    algoStore.createIndex('name', 'name', { unique: false });
                }

                // Models store
                if (!db.objectStoreNames.contains('models')) {
                    const modelStore = db.createObjectStore('models', { keyPath: 'id' });
                    modelStore.createIndex('name', 'name', { unique: false });
                }

                // Data sources store
                if (!db.objectStoreNames.contains('dataSources')) {
                    const dsStore = db.createObjectStore('dataSources', { keyPath: 'name' });
                }

                // Simulation archives store
                if (!db.objectStoreNames.contains('simulationArchives')) {
                    const archiveStore = db.createObjectStore('simulationArchives', { keyPath: 'name' });
                }

                // Cache metadata
                if (!db.objectStoreNames.contains('metadata')) {
                    const metadataStore = db.createObjectStore('metadata', { keyPath: 'key' });
                }
            };
        });
    }

    async put(storeName, data) {
        if (!this.db) await this.init();
        
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.put(data);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve(request.result);
        });
    }

    async get(storeName, key) {
        if (!this.db) await this.init();
        
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readonly');
            const store = transaction.objectStore(storeName);
            const request = store.get(key);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve(request.result);
        });
    }

    async getAll(storeName) {
        if (!this.db) await this.init();
        
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readonly');
            const store = transaction.objectStore(storeName);
            const request = store.getAll();

            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve(request.result);
        });
    }

    async delete(storeName, key) {
        if (!this.db) await this.init();
        
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.delete(key);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve();
        });
    }

    async clear(storeName) {
        if (!this.db) await this.init();
        
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.clear();

            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve();
        });
    }

    async indexGet(storeName, indexName, value) {
        if (!this.db) await this.init();
        
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readonly');
            const store = transaction.objectStore(storeName);
            const index = store.index(indexName);
            const request = index.getAll(value);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve(request.result);
        });
    }

    // Cache metadata for tracking last sync time
    async setCacheMetadata(key, value) {
        return this.put('metadata', { key, value, timestamp: Date.now() });
    }

    async getCacheMetadata(key) {
        const result = await this.get('metadata', key);
        return result ? result.value : null;
    }

    // Check if cache is stale (older than maxAge in milliseconds)
    async isCacheStale(key, maxAge = 5 * 60 * 1000) {
        const result = await this.get('metadata', key);
        if (!result) return true;
        return Date.now() - result.timestamp > maxAge;
    }
}

// Global instance
const localDB = new LocalDB();

// Auto-initialize on load
if (typeof window !== 'undefined') {
    window.localDB = localDB;
    localDB.init().catch(console.error);
}
