// ============================================================
// Stimulus Controller : badge-check
// ============================================================
// Affiche une notification quand un nouveau badge est obtenu.
// Simple controller utilitaire pour les animations futures.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Récupère les badges depuis l'attribut data (JSON)
    const badgesJson = this.element.dataset.badges
    if (!badgesJson) return

    try {
      const badges = JSON.parse(badgesJson)
      if (badges.length > 0) {
        this.showBadgeNotification(badges[0])
        // Petite pluie de confettis dorés pour célébrer le badge obtenu
        this.launchConfetti()
      }
    } catch (e) {
      console.error("BadgeCheck: erreur parsing JSON", e)
    }
  }

  // ============================================================
  // launchConfetti — pluie de confettis dorés (célébration)
  // ============================================================
  // Crée une couche plein écran (.confetti-layer) remplie de petits confettis
  // dorés (.confetti-piece) qui tombent en tournoyant, puis retire le tout
  // une fois l'animation terminée. Styles dans components/_confetti.scss.
  launchConfetti() {
    // Respecte "réduire les animations" : on n'anime rien dans ce cas (sobriété).
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    // Couche plein écran non cliquable qui héberge les confettis
    const layer = document.createElement("div")
    layer.className = "confetti-layer"

    // Nombre de confettis : assez pour la fête, sans surcharger le rendu mobile
    const pieceCount = 36

    for (let i = 0; i < pieceCount; i++) {
      const piece = document.createElement("span")
      piece.className = "confetti-piece"

      // Position horizontale aléatoire sur toute la largeur (0 → 100%)
      piece.style.left = `${Math.random() * 100}%`
      // Durée de chute variable (1.8s → 3.0s) pour un rendu naturel
      piece.style.setProperty("--fall-duration", `${1.8 + Math.random() * 1.2}s`)
      // Léger décalage de départ (0 → 0.6s) pour étaler la pluie dans le temps
      piece.style.setProperty("--fall-delay", `${Math.random() * 0.6}s`)

      layer.appendChild(piece)
    }

    document.body.appendChild(layer)

    // Nettoyage : on retire la couche après 4s (au-delà de la plus longue chute)
    setTimeout(() => layer.remove(), 4000)
  }

  // Affiche une notification Bootstrap pour le badge obtenu
  showBadgeNotification(badge) {
    const toast = document.createElement("div")
    toast.className = "toast align-items-center text-bg-success border-0 position-fixed bottom-0 end-0 m-3"
    toast.setAttribute("role", "alert")
    toast.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">
          🏆 Nouveau badge obtenu : <strong>${badge.icon} ${badge.name}</strong> !
        </div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
      </div>
    `

    document.body.appendChild(toast)

    // Utilise Bootstrap Toast pour afficher la notification
    const bsToast = new bootstrap.Toast(toast, { delay: 5000 })
    bsToast.show()
  }
}
