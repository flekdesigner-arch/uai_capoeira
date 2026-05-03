// =====================================================
// 🔥 SERVICE WORKER - UAI CAPOEIRA PWA
// =====================================================
// Versão: 2.0.26
// Atualize a versão sempre que fizer deploy para forçar update

const CACHE_NAME = 'uai-capoeira-v2.0.26';
const OFFLINE_URL = '/offline.html';
const AUTH_CACHE = 'uai-auth-cache-v1';

// 📦 Recursos para cache inicial
const urlsToCache = [
  '/',
  '/index.html',
  '/offline.html',
  '/manifest.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
  '/flutter.js',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/assets/FontManifest.json',
  '/assets/fonts/MaterialIcons-Regular.otf',
];

// =====================================================
// 📦 INSTALAÇÃO - Cache inicial
// =====================================================
self.addEventListener('install', (event) => {
  console.log('🟢 Service Worker: Instalando v2.0.26...');

  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('📦 Cache aberto, adicionando recursos...');
        return cache.addAll(urlsToCache).catch((error) => {
          console.warn('⚠️ Alguns recursos não foram cacheados:', error);
          return Promise.resolve();
        });
      })
      .then(() => {
        console.log('✅ Instalação completa!');
        return self.skipWaiting();
      })
  );
});

// =====================================================
// 🔄 ATIVAÇÃO - Limpa caches antigos
// =====================================================
self.addEventListener('activate', (event) => {
  console.log('🟢 Service Worker: Ativando...');

  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          // Mantém o cache de autenticação
          if (cacheName !== CACHE_NAME && cacheName !== AUTH_CACHE) {
            console.log('🗑️ Removendo cache antigo:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      console.log('✅ Service Worker ativado!');
      return self.clients.claim();
    })
  );
});

// =====================================================
// 🌐 FETCH - Estratégia otimizada
// =====================================================
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // =====================================================
  // 🔥 FIREBASE AUTH - NUNCA FAZ CACHE (CRÍTICO PARA PERSISTÊNCIA)
  // =====================================================
  if (url.hostname.includes('firebaseauth.googleapis.com') ||
      url.hostname.includes('identitytoolkit.googleapis.com') ||
      url.hostname.includes('securetoken.googleapis.com')) {
    // Deixa passar sem interferência - essencial para login persistir
    return;
  }

  // =====================================================
  // 🔥 FIRESTORE - SEMPRE ONLINE
  // =====================================================
  if (url.hostname.includes('firestore.googleapis.com') ||
      url.hostname.includes('googleapis.com')) {
    return;
  }

  // =====================================================
  // 🔥 ANALYTICS - IGNORA
  // =====================================================
  if (url.hostname.includes('google-analytics.com') ||
      url.hostname.includes('googletagmanager.com')) {
    return;
  }

  // =====================================================
  // 📄 NAVEGAÇÃO (HTML) - Network First
  // =====================================================
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
          return response;
        })
        .catch(() => {
          console.log('📴 Offline - retornando do cache:', event.request.url);
          return caches.match(event.request)
            .then((response) => response || caches.match(OFFLINE_URL));
        })
    );
    return;
  }

  // =====================================================
  // 🖼️ ASSETS - Cache First com atualização em background
  // =====================================================
  event.respondWith(
    caches.match(event.request)
      .then((response) => {
        if (response) {
          // Atualiza o cache em background
          fetch(event.request).then((networkResponse) => {
            if (networkResponse && networkResponse.status === 200) {
              caches.open(CACHE_NAME).then((cache) => {
                cache.put(event.request, networkResponse);
              });
            }
          }).catch(() => {});
          return response;
        }

        // Cache miss - busca da rede
        return fetch(event.request).then((networkResponse) => {
          if (!networkResponse || networkResponse.status !== 200) {
            return networkResponse;
          }

          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache);
          });

          return networkResponse;
        });
      })
      .catch((error) => {
        console.error('❌ Erro no fetch:', error);
        return new Response('', { status: 408 });
      })
  );
});

// =====================================================
// 📨 PUSH NOTIFICATIONS
// =====================================================
self.addEventListener('push', (event) => {
  console.log('📨 Push recebida!');

  let data = {
    title: 'UAI CAPOEIRA',
    body: 'Nova notificação!',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-maskable-192.png',
    vibrate: [200, 100, 200],
    data: { url: '/' },
    actions: [
      { action: 'open', title: 'Abrir' },
      { action: 'close', title: 'Fechar' }
    ]
  };

  if (event.data) {
    try {
      const pushData = event.data.json();
      data = { ...data, ...pushData };
    } catch (e) {
      data.body = event.data.text();
    }
  }

  const options = {
    body: data.body,
    icon: data.icon,
    badge: data.badge,
    vibrate: data.vibrate,
    data: data.data,
    actions: data.actions,
    tag: 'uai-notification',
    renotify: true,
    requireInteraction: true
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// =====================================================
// 🔔 CLIQUE NA NOTIFICAÇÃO
// =====================================================
self.addEventListener('notificationclick', (event) => {
  console.log('🔔 Notificação clicada!');
  event.notification.close();

  if (event.action === 'close') {
    console.log('❌ Usuário fechou a notificação');
    return;
  }

  const urlToOpen = event.notification.data?.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (client.url.includes(urlToOpen) && 'focus' in client) {
            console.log('🔄 Focando janela existente');
            return client.focus();
          }
        }
        if (clients.openWindow) {
          console.log('🆕 Abrindo nova janela:', urlToOpen);
          return clients.openWindow(urlToOpen);
        }
      })
  );
});

// =====================================================
// 🔄 SINCRONIZAÇÃO EM BACKGROUND
// =====================================================
self.addEventListener('sync', (event) => {
  console.log('🔄 Sync em background:', event.tag);

  if (event.tag === 'sync-mensagens') {
    event.waitUntil(syncMensagens());
  }

  if (event.tag === 'sync-dados') {
    event.waitUntil(syncDados());
  }
});

async function syncMensagens() {
  console.log('💬 Sincronizando mensagens...');
  const clients = await self.clients.matchAll();
  clients.forEach(client => {
    client.postMessage({ type: 'sync-complete', tag: 'sync-mensagens' });
  });
}

async function syncDados() {
  console.log('📊 Sincronizando dados...');
  const clients = await self.clients.matchAll();
  clients.forEach(client => {
    client.postMessage({ type: 'sync-complete', tag: 'sync-dados' });
  });
}

// =====================================================
// 📨 MENSAGENS DO CLIENTE
// =====================================================
self.addEventListener('message', (event) => {
  console.log('📨 Mensagem recebida:', event.data);

  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  if (event.data?.type === 'CLEAR_CACHE') {
    event.waitUntil(
      caches.delete(CACHE_NAME).then(() => console.log('🗑️ Cache limpo!'))
    );
  }

  if (event.data?.type === 'CHECK_UPDATE') {
    event.waitUntil(
      self.registration.update().then(() => console.log('🔄 Verificando atualizações...'))
    );
  }
});

console.log('🔥 Service Worker UAI Capoeira v2.0.26 carregado!');