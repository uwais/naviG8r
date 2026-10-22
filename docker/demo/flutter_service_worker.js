// Served in place of the empty file that --pwa-strategy=none writes. Older demo builds installed Flutter's offline
// worker, and a browser keeps it until the worker script changes. This one takes over and, when an old offline copy
// is there, deletes it, removes itself and reloads open tabs from the server. On a clean visit it stays registered
// and does nothing: it has no fetch handler, and Flutter's loader sees it active instead of waiting for it.
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    if (cacheNames.length === 0) return;
    await Promise.all(cacheNames.map((name) => caches.delete(name)));
    await self.registration.unregister();
    const openTabs = await self.clients.matchAll({ type: "window" });
    await Promise.all(openTabs.map((tab) => tab.navigate(tab.url).catch(() => null)));
  })());
});
