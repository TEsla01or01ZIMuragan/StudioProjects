importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyCbyIRsfJrkqx2p0l-KRg8aEkPgQp4ZPPU',
  appId: '1:150747189202:web:b756ddb45e7343c835820b',
  messagingSenderId: '150747189202',
  projectId: 'nanny-crow-s-guide',
  authDomain: 'nanny-crow-s-guide.firebaseapp.com',
  storageBucket: 'nanny-crow-s-guide.firebasestorage.app',
  measurementId: 'G-WTDRR3L3S3',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification ?? {};
  self.registration.showNotification(notification.title ?? 'Nanny Crows', {
    body: notification.body ?? '',
    data: payload.data ?? {},
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(self.clients.openWindow('/'));
});
