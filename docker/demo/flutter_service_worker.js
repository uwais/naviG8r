// Served in place of the empty file that --pwa-strategy=none writes. Older demo builds installed Flutter's offline
// worker, and a browser keeps it until the worker script changes. This one takes over, deletes the old offline copy,
// removes itself and reloads open tabs from the server. Flutter's loader still registers it on each visit; with no
// caches left it only removes itself again, so it never reloads twice.
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((name) => caches.delete(name)));
    await self.registration.unregister();
    if (cacheNames.length === 0) return;
    const openTabs = await self.clients.matchAll({ type: "window" });
    await Promise.all(openTabs.map((tab) => tab.navigate(tab.url).catch(() => null)));
  })());
});
