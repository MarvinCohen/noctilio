// ============================================================
// Stimulus Controller — image-fallback
// ============================================================
// Remplace une couverture d'histoire cassée par un placeholder emoji.
//
// Pourquoi : certaines couvertures sont servies depuis une URL externe
// (fallback Pollinations) qui peut être lente ou indisponible. Sans ce repli,
// le navigateur affiche l'icône d'image cassée + le texte alt (le titre).
// On préfère afficher l'emoji de l'univers de l'histoire, plus propre.
//
// Pourquoi un controller et pas un onerror inline : la Content Security Policy
// du site interdit les gestionnaires d'événements inline (onerror="...").
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // emoji : caractère affiché en repli (ex: "🚀"), passé via data-attribute
  static values = { emoji: String }

  connect() {
    // Cas limite : l'image peut avoir déjà échoué AVANT que Stimulus se branche
    // (image en cache, erreur immédiate). complete=true + naturalWidth=0 = cassée.
    if (this.element.complete && this.element.naturalWidth === 0) {
      this.showPlaceholder()
    }
  }

  // Déclenché par data-action="error->image-fallback#error" sur l'<img>
  error() {
    this.showPlaceholder()
  }

  // Remplace l'<img> par un <div> centré contenant l'emoji de l'univers
  showPlaceholder() {
    const img = this.element

    // Garde-fou : ne jamais remplacer deux fois (connect + event error)
    if (img.dataset.fallbackDone === "true") return
    img.dataset.fallbackDone = "true"

    const placeholder = document.createElement("div")
    // textContent (pas innerHTML) → aucun risque d'injection
    placeholder.textContent = this.emojiValue || "✨"

    // On reprend la classe ET le style inline de l'image pour conserver ses
    // dimensions et arrondis (selon les vues, la taille vient de l'un ou l'autre),
    // puis on impose le centrage + le fond du placeholder emoji.
    placeholder.className = img.className
    placeholder.style.cssText = img.style.cssText
    placeholder.style.display = "flex"
    placeholder.style.alignItems = "center"
    placeholder.style.justifyContent = "center"
    placeholder.style.fontSize = "2.5rem"
    placeholder.style.background = "rgba(240, 201, 122, 0.05)"

    img.replaceWith(placeholder)
  }
}
