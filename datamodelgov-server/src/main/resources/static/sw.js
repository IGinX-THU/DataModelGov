/**
 * Service Worker 已下线(新版工作台要求不走缓存)。
 * 本文件仅负责把历史注册的 SW 与全部缓存清掉;浏览器更新本文件后自动注销。
 */
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
    event.waitUntil((async () => {
        try {
            const keys = await caches.keys();
            await Promise.all(keys.map((k) => caches.delete(k)));
        } catch (e) { /* ignore */ }
        try { await self.registration.unregister(); } catch (e) { /* ignore */ }
        try {
            const clients = await self.clients.matchAll({ type: 'window' });
            clients.forEach((c) => c.navigate(c.url));
        } catch (e) { /* ignore */ }
    })());
});
