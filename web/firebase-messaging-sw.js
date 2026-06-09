// web/firebase-messaging-sw.js
// =====================================================
// 🔥 FIREBASE MESSAGING SERVICE WORKER - UAI CAPOEIRA PWA
// =====================================================
// Este arquivo é obrigatório para o Firebase Cloud Messaging no PWA/Web.
// Ele precisa ficar exatamente em: web/firebase-messaging-sw.js
//
// Objetivo:
// - Receber push no PWA instalado.
// - Evitar notificação duplicada.
// - Se a mensagem já vier com payload.notification, o próprio Firebase/Chrome
//   já mostra a notificação em background.
// - Este service worker só mostra manualmente quando a mensagem for "data-only".
// =====================================================

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyDfwrnXGru6o-ZcHPYRKot6I8UCpM_LC3I",
  authDomain: "uai-capoeira-52753.firebaseapp.com",
  projectId: "uai-capoeira-52753",
  storageBucket: "uai-capoeira-52753.firebasestorage.app",
  messagingSenderId: "570246579920",
  appId: "1:570246579920:web:3af5e719aed0caace480d5",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('🔥 [firebase-messaging-sw.js] Mensagem em background:', payload);

  const notification = payload.notification || {};
  const data = payload.data || {};

  // =====================================================
  // ✅ EVITA DUPLICIDADE NO PWA
  // =====================================================
  // Quando a Cloud Function envia:
  //
  // notification: { title, body }
  //
  // o Firebase/Chrome já exibe a notificação automaticamente
  // quando o PWA está fechado ou em segundo plano.
  //
  // Se chamarmos showNotification aqui de novo,
  // aparecem 2 notificações no PWA.
  // =====================================================
  if (notification.title || notification.body) {
    console.log(
      '✅ Notificação com payload.notification detectada. ' +
      'Deixando Firebase/Chrome exibir automaticamente para evitar duplicidade.'
    );
    return;
  }

  // =====================================================
  // 🔔 CASO DATA-ONLY
  // =====================================================
  // Se no futuro você enviar uma mensagem sem notification,
  // usando só data: { title, body },
  // aí este bloco mostra a notificação manualmente.
  // =====================================================
  const title = data.title || 'UAI CAPOEIRA';

  const options = {
    body: data.body || 'Você recebeu uma nova notificação.',
    icon: data.icon || '/icons/Icon-192.png',
    badge: data.badge || '/icons/Icon-maskable-192.png',
    data: {
      url: data.url || '/',
      tipo: data.tipo || '',
      ...data,
    },
    vibrate: [200, 100, 200],
    tag: data.tag || 'uai-capoeira-notificacao',
    renotify: true,
    requireInteraction: false,
  };

  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  console.log('🔔 [firebase-messaging-sw.js] Notificação clicada:', event.notification);

  event.notification.close();

  const urlToOpen = event.notification?.data?.url || '/';

  event.waitUntil(
    clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          return client.focus();
        }
      }

      if (clients.openWindow) {
        return clients.openWindow(urlToOpen);
      }

      return null;
    })
  );
});

console.log('🔥 Firebase Messaging Service Worker UAI Capoeira carregado sem duplicidade!');