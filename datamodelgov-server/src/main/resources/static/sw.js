/**
 * Service Worker for Offline Support
 * Enables the application to work without external network access
 */

const CACHE_NAME = 'datamodelgov-v1';
const STATIC_CACHE = 'datamodelgov-static-v1';

// Assets to cache for offline use
const STATIC_ASSETS = [
    '/',
    '/index.html',
    '/js/main.js',
    '/js/localdb.js',
    '/js/app-config.js',
    '/js/menu-permission.js',
    '/js/main-menu-permission.js',
    '/js/button-id-mapping.js',
    '/js/modal-manager.js',
    '/js/common-utils.js',
    '/css/variables.css',
    '/css/base-components.css',
    '/components/project-list/project-list.js',
    '/components/project-list/project-list.html',
    '/components/project-list/project-list.css',
    '/components/project-detail/project-detail.js',
    '/components/project-detail/project-detail.html',
    '/components/project-detail/project-detail.css',
    '/components/project-create/project-create.js',
    '/components/project-create/project-create.html',
    '/components/project-create/project-create.css'
];

// Install event - cache static assets
self.addEventListener('install', (event) => {
    console.log('[Service Worker] Installing...');
    
    event.waitUntil(
        caches.open(STATIC_CACHE)
            .then((cache) => {
                console.log('[Service Worker] Caching static assets');
                return cache.addAll(STATIC_ASSETS.map(url => new Request(url, { cache: 'reload' })));
            })
            .catch((error) => {
                console.error('[Service Worker] Failed to cache static assets:', error);
            })
    );
    
    self.skipWaiting();
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
    console.log('[Service Worker] Activating...');
    
    event.waitUntil(
        caches.keys()
            .then((cacheNames) => {
                return Promise.all(
                    cacheNames.map((cacheName) => {
                        if (cacheName !== STATIC_CACHE && cacheName !== CACHE_NAME) {
                            console.log('[Service Worker] Deleting old cache:', cacheName);
                            return caches.delete(cacheName);
                        }
                    })
                );
            })
            .then(() => {
                console.log('[Service Worker] Activation complete');
                return self.clients.claim();
            })
    );
});

// Fetch event - serve from cache, fallback to network
self.addEventListener('fetch', (event) => {
    const url = new URL(event.request.url);
    
    // Skip API calls - they need to go to the server
    if (url.pathname.startsWith('/api/')) {
        event.respondWith(
            fetch(event.request)
                .then((response) => {
                    // Clone response before caching
                    const responseToCache = response.clone();
                    
                    // Cache successful API responses
                    if (response.ok) {
                        caches.open(CACHE_NAME)
                            .then((cache) => {
                                cache.put(event.request, responseToCache);
                            });
                    }
                    
                    return response;
                })
                .catch((error) => {
                    console.error('[Service Worker] API fetch failed:', error);
                    // Try to serve from cache as fallback
                    return caches.match(event.request);
                })
        );
        return;
    }
    
    // For static assets, try cache first, then network
    event.respondWith(
        caches.match(event.request)
            .then((response) => {
                if (response) {
                    return response;
                }
                
                return fetch(event.request)
                    .then((response) => {
                        // Don't cache non-successful responses
                        if (!response || !response.ok) {
                            return response;
                        }
                        
                        // Clone response before caching
                        const responseToCache = response.clone();
                        
                        caches.open(STATIC_CACHE)
                            .then((cache) => {
                                cache.put(event.request, responseToCache);
                            });
                        
                        return response;
                    })
                    .catch((error) => {
                        console.error('[Service Worker] Fetch failed:', error);
                        // Return a fallback for HTML requests
                        if (event.request.mode === 'navigate') {
                            return caches.match('/index.html');
                        }
                    });
            })
    );
});

// Message event - handle messages from clients
self.addEventListener('message', (event) => {
    if (event.data && event.data.type === 'SKIP_WAITING') {
        self.skipWaiting();
    }
    
    if (event.data && event.data.type === 'CACHE_API_DATA') {
        // Cache API data for offline use
        const { request, response } = event.data;
        caches.open(CACHE_NAME)
            .then((cache) => {
                cache.put(request, response);
            });
    }
});

// Sync event - handle background sync
self.addEventListener('sync', (event) => {
    if (event.tag === 'sync-projects') {
        event.waitUntil(syncProjects());
    }
});

// Sync projects with server
async function syncProjects() {
    try {
        // This would sync local changes to the server
        console.log('[Service Worker] Syncing projects...');
        // Implementation depends on your sync strategy
    } catch (error) {
        console.error('[Service Worker] Sync failed:', error);
    }
}
