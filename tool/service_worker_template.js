'use strict';

// Service worker de Hannah's Wallet.
//
// POR QUE ES PROPIO Y NO EL DE FLUTTER
//
// Las versiones recientes de Flutter generan un `flutter_service_worker.js`
// que solo sirve para DESINSTALARSE: se registra, se da de baja y recarga la
// pagina. Ya no cachea nada. Para una app que se instala en la pantalla de
// inicio y presume de funcionar sin conexion, eso significa que abrirla en el
// metro dejaria una pantalla en blanco: los datos estan en el dispositivo,
// pero el codigo que los lee habria que descargarlo.
//
// Este fichero lo sustituye en el build (ver `tool/build_pwa.py`), asi que se
// registra por el mismo camino que el original y no hace falta tocar el
// arranque.
//
// ESTRATEGIA
//
//   * Los recursos de la app (motor, fuentes, iconos) se precargan al
//     instalar y despues se sirven SIEMPRE desde cache: no cambian sin un
//     despliegue nuevo, y cada despliegue estrena version de cache.
//   * El documento va primero a la red y cae a la cache si no hay conexion.
//     Asi una version nueva se recoge en cuanto haya cobertura, en lugar de
//     quedarse pegada la vieja.
//
// Lo que NO toca: IndexedDB. La boveda cifrada es del navegador, no de este
// worker, y borrar caches nunca se lleva por delante los datos del usuario.

const VERSION = '__VERSION__';
const CACHE = 'hannahs-wallet-' + VERSION;
const ASSETS = __ASSETS__;

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // `reload` evita que el propio precache se sirva de una cache HTTP vieja
      // y guarde una version caducada.
      await Promise.all(
        ASSETS.map((url) =>
          cache
            .add(new Request(url, { cache: 'reload' }))
            // Un asset que falle no puede tumbar la instalacion entera: se
            // pedira por red cuando haga falta.
            .catch(() => undefined)
        )
      );
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((k) => k.startsWith('hannahs-wallet-') && k !== CACHE)
          .map((k) => caches.delete(k))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Solo lecturas del propio origen. Las peticiones a terceros no deberian
  // existir -la CSP las bloquea- y desde luego no se cachean.
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // El documento: red primero, cache como red de seguridad.
  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(request);
          const cache = await caches.open(CACHE);
          cache.put('index.html', fresh.clone());
          return fresh;
        } catch (_) {
          const cached =
            (await caches.match('index.html')) || (await caches.match('/'));
          return cached || Response.error();
        }
      })()
    );
    return;
  }

  // Todo lo demas: cache primero.
  event.respondWith(
    (async () => {
      const cached = await caches.match(request, { ignoreSearch: true });
      if (cached) return cached;
      try {
        const fresh = await fetch(request);
        if (fresh && fresh.ok && fresh.type === 'basic') {
          const cache = await caches.open(CACHE);
          cache.put(request, fresh.clone());
        }
        return fresh;
      } catch (_) {
        return Response.error();
      }
    })()
  );
});
