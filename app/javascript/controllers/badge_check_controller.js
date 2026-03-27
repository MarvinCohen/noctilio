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
      }
    } catch (e) {
      console.error("BadgeCheck: erreur parsing JSON", e)
    }
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
