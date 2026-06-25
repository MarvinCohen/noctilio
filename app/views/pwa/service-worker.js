// ============================================================
// Service Worker Noctilio
// ============================================================
// Ce fichier tourne en arrière-plan dans le navigateur, séparé
// de la page. Il intercepte les requêtes réseau pour mettre en
// cache les assets statiques — ce qui permet :
//   1. Un chargement plus rapide (servi depuis le cache)
//   2. Un affichage partiel même sans réseau (offline)
// ============================================================

// Nom du cache — change ce nom pour forcer la mise à jour du cache
// lors d'un nouveau déploiement (ex: "noctilio-v3").
// Bumpé en v2 : nouvelles icônes PWA dédiées + correction de la liste de pré-cache.
const CACHE_NAME = "noctilio-v2";

// Liste des URLs "coquilles" à mettre en cache dès l'installation.
// IMPORTANT : addAll échoue en bloc si UNE seule URL renvoie une erreur (404).
// On ne liste donc que des routes réellement existantes (avant : "/dashboard"
// et "/offline" n'existaient pas → le pré-cache échouait toujours en silence).
const URLS_TO_CACHE = [
  "/",      // Landing page (publique)
  "/home"   // Dashboard — page principale après connexion (= start_url du manifest)
];

// ============================================================
// Événement "install" — déclenché quand le service worker
// est installé pour la première fois (ou mis à jour)
// ============================================================
self.addEventListener("install", function(event) {
  // waitUntil garantit que le service worker attend la fin du
  // cache avant de passer à l'état "activé"
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      // On tente de pré-cacher les URLs essentielles
      // addAll échoue silencieusement si une URL est inaccessible
      return cache.addAll(URLS_TO_CACHE).catch(function() {
        // Si le pré-cache échoue (ex: pas de réseau), on continue quand même
        // L'app fonctionnera normalement en ligne
      });
    })
  );
  // skipWaiting : active immédiatement le nouveau service worker
  // sans attendre que l'ancienne version soit déchargée
  self.skipWaiting();
});

// ============================================================
// Événement "activate" — déclenché quand le service worker
// prend le contrôle des pages (après install)
// ============================================================
self.addEventListener("activate", function(event) {
  event.waitUntil(
    caches.keys().then(function(cacheNames) {
      // Supprime tous les caches qui ne correspondent plus au nom actuel
      // Cela nettoie les vieux caches des versions précédentes
      return Promise.all(
        cacheNames
          .filter(function(name) { return name !== CACHE_NAME; })
          .map(function(name) { return caches.delete(name); })
      );
    })
  );
  // Prend le contrôle de toutes les pages ouvertes immédiatement
  self.clients.claim();
});

// ============================================================
// Événement "fetch" — intercepte chaque requête réseau
// Stratégie : Network First (réseau d'abord, cache en fallback)
// ============================================================
// Network First = on essaie toujours le réseau pour avoir du contenu frais.
// Si le réseau échoue (offline), on répond depuis le cache.
// Idéal pour une app avec du contenu dynamique (histoires générées par IA).
// ============================================================
self.addEventListener("fetch", function(event) {
  // On n'intercepte que les requêtes GET
  // Les POST (formulaires, création d'histoires) ne sont jamais mis en cache
  if (event.request.method !== "GET") return;

  // On n'intercepte pas les requêtes vers des domaines externes
  // (Google Fonts, Cloudinary, OpenAI, Stripe...)
  const url = new URL(event.request.url);
  if (url.origin !== location.origin) return;

  event.respondWith(
    fetch(event.request)
      .then(function(networkResponse) {
        // On ne met en cache que les réponses "saines" (status 200, type basique).
        // Évite de cacher des redirections (302 vers la connexion), des erreurs
        // ou des réponses opaques qui rendraient la lecture hors-ligne incohérente.
        if (networkResponse.ok && networkResponse.type === "basic") {
          // clone() est nécessaire car une Response ne peut être lue qu'une fois
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then(function(cache) {
            cache.put(event.request, responseToCache);
          });
        }
        return networkResponse;
      })
      .catch(function() {
        // Le réseau a échoué (hors ligne) — on cherche d'abord la page exacte
        // en cache. C'est ce qui permet de relire une histoire déjà ouverte.
        return caches.match(event.request).then(function(cachedResponse) {
          if (cachedResponse) return cachedResponse;

          // Pas de version exacte en cache. Pour une navigation (ouverture d'une
          // page), on sert la coquille du dashboard en repli plutôt qu'un écran
          // blanc — l'utilisateur garde un point d'entrée vers l'app.
          if (event.request.mode === "navigate") {
            return caches.match("/home").then(function(shell) {
              return shell || new Response("", { status: 503, statusText: "Hors ligne" });
            });
          }

          // Autres requêtes (image, audio non caché…) : réponse vide générique
          return new Response("", { status: 503, statusText: "Service indisponible" });
        });
      })
  );
});

// ============================================================
// Événement "push" — réception d'une notification push du serveur
// ============================================================
// Déclenché même app fermée (le service worker tourne en arrière-plan).
// Le serveur envoie un payload JSON { title, body, url } via web-push ;
// on l'affiche sous forme de notification système.
self.addEventListener("push", function(event) {
  // Payload par défaut si jamais le message arrive vide ou illisible
  let data = { title: "Noctilio", body: "Une histoire t'attend ✦", url: "/" };
  try {
    if (event.data) data = event.data.json();
  } catch (e) {
    // Payload non-JSON : on garde les valeurs par défaut
  }

  const options = {
    body: data.body,
    icon: "/icon-192.png",   // icône PWA déjà servie (voir manifest)
    badge: "/icon-192.png",  // petite icône monochrome (Android)
    // data.url est relu dans "notificationclick" pour ouvrir la bonne page
    data: { url: data.url || "/" }
  };

  // waitUntil garde le service worker en vie le temps d'afficher la notif
  event.waitUntil(
    self.registration.showNotification(data.title || "Noctilio", options)
  );
});

// ============================================================
// Événement "notificationclick" — clic sur la notification
// ============================================================
// Ferme la notif puis ouvre (ou met au premier plan) l'app sur l'URL fournie.
self.addEventListener("notificationclick", function(event) {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || "/";

  event.waitUntil(
    // Si un onglet de l'app est déjà ouvert, on le réutilise ; sinon on en ouvre un.
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(function(clientList) {
      for (const client of clientList) {
        if ("focus" in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});
