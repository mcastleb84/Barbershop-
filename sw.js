// Lets phones install the site as an app. It never keeps old copies of this site's pages,
// so the apps always open the newest version and live booking times.
self.addEventListener('install', function(){ self.skipWaiting(); });
self.addEventListener('activate', function(e){ e.waitUntil(self.clients.claim()); });
self.addEventListener('fetch', function(e){
  if (e.request.method !== 'GET') return;
  var same = new URL(e.request.url).origin === self.location.origin;
  if (!same){ e.respondWith(fetch(e.request)); return; }
  e.respondWith(fetch(e.request.url, {cache: 'no-store', credentials: 'same-origin'}).catch(function(){ return fetch(e.request); }));
});
