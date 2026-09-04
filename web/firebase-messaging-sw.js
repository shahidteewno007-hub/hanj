importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyAn3syfknc5Z5DHhCDBZApog6GVgTgva3g",
  authDomain: "anime-tracker-275cc.firebaseapp.com",
  projectId: "anime-tracker-275cc",
  storageBucket: "anime-tracker-275cc.firebasestorage.app",
  messagingSenderId: "572595796065",
  appId: "1:572595796065:web:83130c14d521f706fd5220"
});

const messaging = firebase.messaging();

// Background message handler — fires when app is not in focus
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};

  const title = notification.title || data.title || "Aruku";
  const body  = notification.body  || data.body  || "";
  const icon  = notification.icon  || "/icons/Icon-192.png";

  // Map notification type to a friendly tag (collapses dupes)
  const tag = data.type
    ? `aruku-${data.type}-${data.animeId || Date.now()}`
    : `aruku-${Date.now()}`;

  return self.registration.showNotification(title, {
    body,
    icon,
    badge: "/icons/Icon-192.png",
    tag,
    data: data,
    vibrate: [200, 100, 200],
  });
});

// Notification click — focus/open the app
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clientList) => {
        // If app tab already open, focus it
        for (const client of clientList) {
          if ("focus" in client) return client.focus();
        }
        // Otherwise open a new tab
        return clients.openWindow("/");
      })
  );
});
