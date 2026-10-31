// Firebase Cloud Messaging Service Worker for Flutter Web
// This script serves as the service worker endpoint for push notification registration.
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  if (event.data) {
    try {
      const payload = event.data.json();
      const title = payload.notification?.title || payload.data?.title || 'PalengkeGo';
      const options = {
        body: payload.notification?.body || payload.data?.body || '',
        icon: '/icons/Icon-192.png',
        data: payload.data,
      };
      event.waitUntil(self.registration.showNotification(title, options));
    } catch (_) {}
  }
});
