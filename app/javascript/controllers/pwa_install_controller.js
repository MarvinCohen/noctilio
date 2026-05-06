// ============================================================
// PWA Install Controller — Stimulus
// ============================================================
// Ce controller gère le bouton "Installer l'application".
//
// Fonctionnement :
//   1. Le navigateur déclenche "beforeinstallprompt" quand l'app
//      est éligible à l'installation (HTTPS + service worker actif)
//   2. On capture cet événement et on affiche le bouton
//   3. Au clic, on déclenche le dialogue d'installation natif
//   4. Après installation, on cache le bouton définitivement
//
// Le bouton est CACHÉ par défaut (style="display:none").
// Il n'apparaît que si le navigateur le permet ET que l'app
// n'est pas déjà installée.
// ============================================================

import { Controller } from "@hotwired/stimulus"

// Variable globale pour stocker l'événement d'installation
// Elle est déclarée EN DEHORS de la classe pour survivre aux
// navigations Turbo (la classe est ré-instanciée, la variable non)
let deferredPrompt = null;

// On capture l'événement le plus tôt possible, avant même que
// Stimulus soit prêt — sinon on le rate au premier chargement
window.addEventListener("beforeinstallprompt", function(event) {
  // Empêche le navigateur d'afficher son propre bandeau automatique
  event.preventDefault();
  // On sauvegarde l'événement pour le déclencher au clic
  deferredPrompt = event;
});

export default class extends Controller {

  // ── connect() est appelé quand le bouton apparaît dans le DOM ──
  connect() {
    // Si l'app est déjà installée (mode standalone = lancée depuis l'écran d'accueil),
    // on cache le bouton — inutile de proposer une installation déjà faite
    const isStandalone =
      window.matchMedia("(display-mode: standalone)").matches || // Android / Chrome
      window.navigator.standalone === true;                      // iOS / Safari

    if (isStandalone) {
      this.element.style.display = "none";
      return;
    }

    // Si le prompt est déjà disponible (page rechargée après navigation),
    // on affiche immédiatement le bouton
    if (deferredPrompt) {
      this.element.style.display = "inline-flex";
    }

    // Stocke les fonctions liées pour pouvoir les supprimer plus tard
    // (bind() crée un nouvel objet à chaque appel, il faut le mémoriser)
    this._onInstallPrompt = this._handleInstallPrompt.bind(this);
    this._onInstalled     = this._handleInstalled.bind(this);

    // Écoute les futurs événements — utile si on navigue entre pages Turbo
    window.addEventListener("beforeinstallprompt", this._onInstallPrompt);

    // "appinstalled" se déclenche quand l'utilisateur vient d'installer l'app
    window.addEventListener("appinstalled", this._onInstalled);
  }

  // ── disconnect() est appelé quand le bouton quitte le DOM ──
  // On nettoie les écouteurs pour éviter les fuites mémoire
  disconnect() {
    if (this._onInstallPrompt) {
      window.removeEventListener("beforeinstallprompt", this._onInstallPrompt);
    }
    if (this._onInstalled) {
      window.removeEventListener("appinstalled", this._onInstalled);
    }
  }

  // ── install() — action déclenchée au clic sur le bouton ──
  async install() {
    // Si le prompt n'est pas disponible (Safari iOS ou déjà installé), on sort
    if (!deferredPrompt) return;

    // Affiche le dialogue natif du navigateur ("Ajouter à l'écran d'accueil")
    deferredPrompt.prompt();

    // Attend la réponse de l'utilisateur (accepted / dismissed)
    const { outcome } = await deferredPrompt.userChoice;

    if (outcome === "accepted") {
      // L'utilisateur a accepté → on vide le prompt et on cache le bouton
      deferredPrompt = null;
      this.element.style.display = "none";
    }
    // Si "dismissed" : l'utilisateur a refusé, on laisse le bouton visible
    // pour qu'il puisse réessayer plus tard
  }

  // ── Méthodes privées (convention : préfixe _) ──

  // Appelée quand le navigateur déclare l'app installable
  _handleInstallPrompt(event) {
    event.preventDefault();
    deferredPrompt = event;
    // Montre le bouton — l'app est désormais installable
    this.element.style.display = "inline-flex";
  }

  // Appelée quand l'app vient d'être installée avec succès
  _handleInstalled() {
    deferredPrompt = null;
    // Cache le bouton — l'app est installée, plus besoin de le proposer
    this.element.style.display = "none";
  }
}
