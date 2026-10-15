
// PATCH TRACKING 01 — console silencioso no PWA.
const uaiConsole = {
  log: () => {},
  info: () => {},
  warn: () => {},
  error: () => {},
  debug: () => {},
};

// =====================================================
// 🔥 SERVICE WORKER - UAI CAPOEIRA PWA
// =====================================================
// Versão: 2.0.117 - PATCH SITE 09 CACHE/OFFLINE PRO
// Atualize a versão sempre que fizer deploy para forçar update

const CACHE_NAME = 'uai-capoeira-v2.0.117-site09-pro';
const OFFLINE_URL = '/offline.html';
const AUTH_CACHE = 'uai-auth-cache-v1';

const SHELL_URL = '/';
const SENSITIVE_QUERY_KEYS = [
  'token',
  'code',
  'oobCode',
  'mode',
  'apiKey',
  'continueUrl',
];

function isSensitiveNavigation(url) {
  if (url.origin !== self.location.origin) return true;

  for (const key of SENSITIVE_QUERY_KEYS) {
    if (url.searchParams.has(key)) return true;
  }

  const path = url.pathname.toLowerCase();
  return path.includes('/ativar') ||
         path.includes('/login') ||
         path.includes('/auth') ||
         path.includes('/minha-uai/ativar') ||
         path.includes('/area-aluno/ativar');
}

function shouldCacheResponse(response) {
  return !!response &&
         response.status === 200 &&
         (response.type === 'basic' || response.type === 'cors');
}


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
];

// =====================================================
// 📦 INSTALAÇÃO - Cache inicial
// =====================================================
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        return cache.addAll(urlsToCache).catch((error) => {
          return Promise.resolve();
        });
      })
      .then(() => {
        return self.skipWaiting();
      })
  );
});

// =====================================================
// 🔄 ATIVAÇÃO - Limpa caches antigos
// =====================================================
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          // Mantém o cache de autenticação
          if (cacheName !== CACHE_NAME && cacheName !== AUTH_CACHE) {
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
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
  // 📄 NAVEGAÇÃO (HTML) - Network First seguro
  // Só o shell público é persistido. URLs com token/login/ativação não são
  // gravadas em cache para evitar reuso indevido de links sensíveis.
  // =====================================================
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (!isSensitiveNavigation(url) && shouldCacheResponse(response)) {
            const responseClone = response.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(SHELL_URL, responseClone);
            });
          }
          return response;
        })
        .catch(async () => {
          if (!isSensitiveNavigation(url)) {
            const shell = await caches.match(SHELL_URL);
            if (shell) return shell;
          }

          const offline = await caches.match(OFFLINE_URL);
          return offline || new Response(
            '<h1>UAI Capoeira offline</h1>',
            { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8' } }
          );
        })
    );
    return;
  }

  // =====================================================
  // ⚡ BOOT FLUTTER - CACHE FIRST + REVALIDAÇÃO EM BACKGROUND
  // Após a primeira carga, o PWA não espera rede para main/chunks.
  // CACHE_NAME versionado impede eternizar bundle de release anterior.
  // =====================================================
  if (url.origin === self.location.origin &&
      (url.pathname.endsWith('/flutter_bootstrap.js') ||
       url.pathname.endsWith('/flutter.js') ||
       url.pathname.endsWith('/main.dart.js') ||
       url.pathname.includes('.part.js'))) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        const networkUpdate = fetch(event.request)
          .then((response) => {
            if (shouldCacheResponse(response)) {
              const clone = response.clone();
              caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
            }
            return response;
          })
          .catch(() => null);

        if (cached) {
          // Atualiza sem bloquear esta abertura.
          event.waitUntil(networkUpdate);
          return cached;
        }

        return networkUpdate.then((response) =>
          response || new Response('', { status: 408 })
        );
      })
    );
    return;
  }

  // =====================================================
  // 🖼️ ASSETS - Cache First real
  // O CACHE_NAME é versionado por release, então assets já encontrados não
  // precisam gerar uma segunda requisição de rede em cada abertura do PWA.
  // Isso reduz tráfego/CPU pós-paint sem alterar o boot nem os módulos internos.
  // =====================================================
  event.respondWith(
    caches.match(event.request)
      .then((cached) => {
        if (cached) return cached;

        return fetch(event.request).then((networkResponse) => {
          if (!shouldCacheResponse(networkResponse)) {
            return networkResponse;
          }

          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache);
          });

          return networkResponse;
        });
      })
      .catch(() => new Response('', { status: 408 }))
  );
});

// =====================================================
// 📨 PUSH NOTIFICATIONS
// =====================================================
self.addEventListener('push', (event) => {
  uaiConsole.log('📨 Push recebida!');

  let data = {
    title: 'UAI Capoeira',
    body: 'Você recebeu um novo aviso do UAI Capoeira.',
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
      const notif = pushData.notification || {};
      const payloadData = pushData.data || {};
      data = {
        ...data,
        ...pushData,
        ...payloadData,
        title: notif.title || payloadData.title || pushData.title || data.title,
        body: notif.body || payloadData.body || pushData.body || data.body,
        data: {
          ...(data.data || {}),
          ...payloadData,
        },
      };
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
  uaiConsole.log('🔔 Notificação clicada!');
  event.notification.close();

  if (event.action === 'close') {
    uaiConsole.log('❌ Usuário fechou a notificação');
    return;
  }

  const urlToOpen = event.notification.data?.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (client.url.includes(urlToOpen) && 'focus' in client) {
            uaiConsole.log('🔄 Focando janela existente');
            return client.focus();
          }
        }
        if (clients.openWindow) {
          uaiConsole.log('🆕 Abrindo nova janela:', urlToOpen);
          return clients.openWindow(urlToOpen);
        }
      })
  );
});

// =====================================================
// 🔄 SINCRONIZAÇÃO EM BACKGROUND
// =====================================================
self.addEventListener('sync', (event) => {
  uaiConsole.log('🔄 Sync em background:', event.tag);

  if (event.tag === 'sync-mensagens') {
    event.waitUntil(syncMensagens());
  }

  if (event.tag === 'sync-dados') {
    event.waitUntil(syncDados());
  }
});

async function syncMensagens() {
  uaiConsole.log('💬 Sincronizando mensagens...');
  const clients = await self.clients.matchAll();
  clients.forEach(client => {
    client.postMessage({ type: 'sync-complete', tag: 'sync-mensagens' });
  });
}

async function syncDados() {
  uaiConsole.log('📊 Sincronizando dados...');
  const clients = await self.clients.matchAll();
  clients.forEach(client => {
    client.postMessage({ type: 'sync-complete', tag: 'sync-dados' });
  });
}

// =====================================================
// 📨 MENSAGENS DO CLIENTE
// =====================================================
self.addEventListener('message', (event) => {
  uaiConsole.log('📨 Mensagem recebida:', event.data);

  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  if (event.data?.type === 'CLEAR_CACHE') {
    event.waitUntil(
      caches.delete(CACHE_NAME).then(() => uaiConsole.log('🗑️ Cache limpo!'))
    );
  }

  if (event.data?.type === 'CHECK_UPDATE') {
    event.waitUntil(
      self.registration.update().then(() => uaiConsole.log('🔄 Verificando atualizações...'))
    );
  }
});

uaiConsole.log('🔥 Service Worker UAI Capoeira - cache/offline pro carregado!');