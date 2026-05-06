// ============================================================
// Flash Autohide Controller — Stimulus
// ============================================================
// Ce controller ferme automatiquement les toasts flash
// (notices de connexion, confirmations, erreurs) après 4 secondes.
//
// Fonctionnement :
//   1. connect() est appelé dès que le toast apparaît dans le DOM
//   2. On lance un timer de 4 secondes
//   3. À expiration, on déclenche le bouton de fermeture Bootstrap
//      (qui gère l'animation de disparition avec la classe "fade")
//   4. Si l'utilisateur ferme manuellement avant, le timer est annulé
//      dans disconnect() pour éviter une erreur sur un élément supprimé
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ── connect() — déclenché dès que le toast entre dans le DOM ──
  connect() {
    // Lance le timer : 4000ms = 4 secondes avant disparition automatique
    // On stocke l'ID pour pouvoir l'annuler dans disconnect()
    this._timer = setTimeout(() => {
      this._close();
    }, 4000);
  }

  // ── disconnect() — déclenché quand le toast quitte le DOM ──
  // (fermeture manuelle via le bouton ×)
  disconnect() {
    // Annule le timer si l'utilisateur a déjà fermé manuellement
    // Sans ça, le setTimeout essaierait d'agir sur un élément supprimé
    clearTimeout(this._timer);
  }

  // ── _close() — ferme le toast avec l'animation Bootstrap ──
  _close() {
    // On clique sur le bouton de fermeture Bootstrap
    // Bootstrap gère l'animation "fade out" et retire l'élément du DOM
    const closeBtn = this.element.querySelector(".btn-close");
    if (closeBtn) closeBtn.click();
  }
}
