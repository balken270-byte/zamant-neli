// ============================================================
// KLİPSY — Service Worker  (v2)
// Ne işe yarar: Android'in uygulamayı "kurulabilir" sayması için gerekli.
// ÖNEMLİ: HTML sayfası ASLA önbellekten servis edilmez — böylece
// eski sürümde takılma olmaz. Sadece ikon/manifest önbelleğe alınır.
// ============================================================

const CACHE = 'klipsy-v2';
const ASSETS = ['./icon.png', './manifest.json'];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS).catch(() => {})));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.map((k) => caches.delete(k))))  // eski her şeyi sil
      .then(() => caches.open(CACHE).then((c) => c.addAll(ASSETS).catch(() => {})))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // Supabase/CDN'e dokunma

  const isHTML =
    req.mode === 'navigate' ||
    (req.headers.get('accept') || '').includes('text/html') ||
    url.pathname.endsWith('.html') ||
    url.pathname === '/' ;

  // HTML: her zaman ağdan al, önbelleğe alma (eski sürüm takılmasın)
  if (isHTML) {
    e.respondWith(fetch(req, { cache: 'no-store' }).catch(() => fetch(req)));
    return;
  }

  // diğer yerel dosyalar: önce önbellek, yoksa ağ
  e.respondWith(
    caches.match(req).then((hit) =>
      hit || fetch(req).then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy).catch(() => {}));
        }
        return res;
      })
    )
  );
});
