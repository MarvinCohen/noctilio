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
// lors d'un nouveau déploiement (ex: "noctilio-v2")
const CACHE_NAME = "noctilio-v1";

// Liste des URLs à mettre en cache immédiatement à l'installation
// On cache uniquement les pages "coquilles" essentielles
const URLS_TO_CACHE = [
  "/",           // Landing page
  "/dashboard",  // Page principale après connexion
  "/offline"     // Page affichée si l'utilisateur est hors ligne (optionnel)
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
        // Si le réseau répond, on met la réponse en cache pour plus tard
        // clone() est nécessaire car une Response ne peut être lue qu'une fois
        const responseToCache = networkResponse.clone();
        caches.open(CACHE_NAME).then(function(cache) {
          cache.put(event.request, responseToCache);
        });
        return networkResponse;
      })
      .catch(function() {
        // Le réseau a échoué — on cherche dans le cache
        return caches.match(event.request).then(function(cachedResponse) {
          // Si on a une version en cache, on la retourne
          if (cachedResponse) return cachedResponse;
          // Sinon, on retourne une réponse vide générique (évite un écran blanc)
          return new Response("", { status: 503, statusText: "Service indisponible" });
        });
      })
  );
});
