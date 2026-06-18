// ============================================================
// Share Controller — Stimulus
// ============================================================
// Gère le bouton "Copier le lien" de partage d'une histoire.
// Le lien de partage (URL publique signée) est rendu côté serveur dans un
// attribut data-share-url-value. Au clic, on le copie dans le presse-papiers
// et on affiche une confirmation visuelle temporaire ("Lien copié !").
//
// Le bouton WhatsApp, lui, est un simple lien <a> (pas besoin de JS).
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // url : l'URL publique de partage (passée depuis la vue)
  // copied : texte de confirmation "Lien copié !" (traduit, passé depuis la vue)
  // button : le bouton "Copier le lien" dont on change le texte après copie
  static values = { url: String, copied: String }
  static targets = ["button"]

  // ── copy() — copie l'URL de partage dans le presse-papiers ──
  copy() {
    // navigator.clipboard est l'API moderne (nécessite HTTPS, ok en prod)
    navigator.clipboard.writeText(this.urlValue)
      .then(() => this._showCopied())   // succès → confirmation visuelle
      .catch(() => this._fallbackCopy()); // échec (vieux navigateur) → méthode de secours
  }

  // ── _showCopied() — remplace le texte du bouton pendant 2 secondes ──
  _showCopied() {
    if (!this.hasButtonTarget) return;

    // Mémorise le texte d'origine pour le restaurer ensuite
    const original = this.buttonTarget.dataset.originalLabel || this.buttonTarget.textContent;
    this.buttonTarget.dataset.originalLabel = original;
    this.buttonTarget.textContent = this.copiedValue;

    // Restaure le texte d'origine après 2 secondes
    setTimeout(() => {
      this.buttonTarget.textContent = this.buttonTarget.dataset.originalLabel;
    }, 2000);
  }

  // ── _fallbackCopy() — copie via une zone de texte temporaire ──
  // Pour les navigateurs sans navigator.clipboard (ou contexte non sécurisé)
  _fallbackCopy() {
    const textarea = document.createElement("textarea");
    textarea.value = this.urlValue;
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy"); // API obsolète mais largement supportée
    document.body.removeChild(textarea);
    this._showCopied();
  }
}
