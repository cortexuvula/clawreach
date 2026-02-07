// ClawReach Service Worker
// Handles push notifications and offline caching for web platform

const CACHE_NAME = 'clawreach-v2';
const DATA_CACHE_NAME = 'clawreach-data-v1';

// Core app shell (always cache)
const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
];

// Runtime cache (cache on first fetch)
const RUNTIME_CACHE = [
  '/main.dart.js',
  '/flutter.js',
  '/flutter_service_worker.js',
];

// Network-first resources (API calls, dynamic content)
const NETWORK_FIRST = [
  '/api/',
  '/ws/',
  '/__openclaw__/',
];

// Install event - cache app shell
self.addEventListener('install', (event) => {
  console.log('[SW] Installing service worker...');
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('[SW] Caching app shell:', APP_SHELL);
        return cache.addAll(APP_SHELL).catch((err) => {
          console.warn('[SW] Cache add failed (expected during dev):', err);
        });
      })
  );
  // Force immediate activation
  self.skipWaiting();
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  console.log('[SW] Activating service worker...');
  const currentCaches = [CACHE_NAME, DATA_CACHE_NAME];
  
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (!currentCaches.includes(cacheName)) {
            console.log('[SW] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  // Take control of all pages immediately
  return self.clients.claim();
});

// Fetch event - smart caching strategies
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  
  // Skip cross-origin requests
  if (url.origin !== location.origin) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Network-first for API/WebSocket requests
  if (NETWORK_FIRST.some(pattern => url.pathname.startsWith(pattern))) {
    event.respondWith(networkFirst(event.request));
    return;
  }

  // Cache-first for app shell and assets
  event.respondWith(cacheFirst(event.request));
});

// Cache-first strategy (app shell, static assets)
async function cacheFirst(request) {
  try {
    const cached = await caches.match(request);
    if (cached) {
      console.log('[SW] Cache hit:', request.url);
      return cached;
    }

    console.log('[SW] Cache miss, fetching:', request.url);
    const response = await fetch(request);
    
    if (response && response.status === 200 && response.type === 'basic') {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    
    return response;
  } catch (err) {
    console.warn('[SW] Fetch failed:', err);
    
    // Try to return cached version as fallback
    const cached = await caches.match(request);
    if (cached) {
      console.log('[SW] Returning stale cache (offline)');
      return cached;
    }
    
    // Return offline page
    return new Response('Offline - ClawReach is not available', {
      status: 503,
      statusText: 'Service Unavailable',
      headers: new Headers({
        'Content-Type': 'text/plain'
      })
    });
  }
}

// Network-first strategy (API, dynamic content)
async function networkFirst(request) {
  try {
    const response = await fetch(request);
    
    // Cache successful responses
    if (response && response.status === 200) {
      const cache = await caches.open(DATA_CACHE_NAME);
      cache.put(request, response.clone());
    }
    
    return response;
  } catch (err) {
    console.warn('[SW] Network failed, trying cache:', err);
    
    // Fallback to cache
    const cached = await caches.match(request);
    if (cached) {
      console.log('[SW] Returning cached data (offline)');
      return cached;
    }
    
    throw err;
  }
}

// Push event - handle push notifications
self.addEventListener('push', (event) => {
  console.log('[SW] Push notification received');

  let data = {
    title: 'Fred 🦊',
    body: 'New message',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };

  if (event.data) {
    try {
      data = event.data.json();
    } catch (e) {
      data.body = event.data.text();
    }
  }

  const options = {
    body: data.body,
    icon: data.icon || '/icons/Icon-192.png',
    badge: data.badge || '/icons/Icon-192.png',
    tag: data.tag || 'clawreach-notification',
    requireInteraction: data.requireInteraction || false,
    data: data.data || {},
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// Notification click event - open app
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Notification clicked');
  event.notification.close();

  // Open ClawReach window or focus existing one
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // Check if a ClawReach window is already open
        for (let client of clientList) {
          if (client.url === '/' && 'focus' in client) {
            return client.focus();
          }
        }
        // Open new window if none found
        if (clients.openWindow) {
          return clients.openWindow('/');
        }
      })
  );
});

// Background sync event (future enhancement)
self.addEventListener('sync', (event) => {
  console.log('[SW] Background sync:', event.tag);
  if (event.tag === 'sync-messages') {
    event.waitUntil(syncMessages());
  }
});

async function syncMessages() {
  // Placeholder for background message sync
  console.log('[SW] Syncing messages...');
  // Could fetch pending messages when back online
}

// Periodic background sync (future enhancement - requires permission)
self.addEventListener('periodicsync', (event) => {
  console.log('[SW] Periodic sync:', event.tag);
  if (event.tag === 'check-updates') {
    event.waitUntil(checkForUpdates());
  }
});

async function checkForUpdates() {
  // Placeholder for periodic update checks
  console.log('[SW] Checking for updates...');
}

console.log('[SW] Service worker loaded');
