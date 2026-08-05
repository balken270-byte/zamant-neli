// ============================================================
// KLİPSY — Service Worker
// Ne işe yarar: Android'in uygulamayı "kurulabilir" sayması için
// zorunlu. Ayrıca temel dosyaları önbelleğe alıp açılışı hızlandırır.
// Not: Anlar/fotoğraflar ÖNBELLEĞE ALINMAZ — sadece uygulama iskeleti.
// ============================================================

const CACHE = 'klipsy-v1';
const CORE = ['./', './index.html', './manifest.json', './icon.png'];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(CORE).catch(() => {}))
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Supabase, iTunes, harita, CDN → asla önbelleğe alma, hep ağdan
  if (url.origin !== self.location.origin) return;

  // uygulama dosyaları: önce ağ, olmazsa önbellek
  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy).catch(() => {}));
        }
        return res;
      })
      .catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
  );
});
