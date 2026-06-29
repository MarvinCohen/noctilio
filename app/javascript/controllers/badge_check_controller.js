// ============================================================
// Stimulus Controller : badge-check
// ============================================================
// Affiche une notification quand un nouveau badge est obtenu.
// Simple controller utilitaire pour les animations futures.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // seenUrl : endpoint POST /badges/vus appelé une fois la célébration affichée,
  // pour que ces badges ne soient plus re-notifiés au prochain chargement.
  static values = { seenUrl: String }

  connect() {
    // Récupère les badges depuis l'attribut data (JSON)
    const badgesJson = this.element.dataset.badges
    if (!badgesJson) return

    try {
      const badges = JSON.parse(badgesJson)
      if (badges.length > 0) {
        // On n'affiche que le PREMIER badge en toast (évite d'empiler les toasts),
        // mais on lance une seule pluie de confettis pour l'ensemble.
        this.showBadgeNotification(badges[0])
        this.launchConfetti()
        // On prévient le serveur que ces badges ont été fêtés : ils passent
        // notified: true et ne réapparaîtront plus.
        this.markSeen()
      }
    } catch (e) {
      console.error("BadgeCheck: erreur parsing JSON", e)
    }
  }

  // ============================================================
  // markSeen — accuse réception de la notification côté serveur
  // ============================================================
  // POST /badges/vus avec le token CSRF (lu dans la balise meta du layout).
  // En cas d'échec réseau, on ne bloque rien : les badges resteront simplement
  // "à notifier" et seront re-proposés au prochain chargement (comportement sûr).
  markSeen() {
    if (!this.hasSeenUrlValue) return

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.seenUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrf,
        "Accept": "application/json"
      }
    }).catch((e) => console.error("BadgeCheck: échec markSeen", e))
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

  // Affiche une notification (toast) pour le badge obtenu.
  // Implémentation AUTONOME : on ne dépend pas du global `bootstrap` (non exposé
  // de façon fiable via importmap). On gère l'affichage et la disparition à la
  // main, tout en réutilisant les classes de style Bootstrap pour la cohérence.
  showBadgeNotification(badge) {
    const toast = document.createElement("div")
    toast.className = "toast show align-items-center text-bg-success border-0 position-fixed bottom-0 end-0 m-3"
    toast.style.zIndex = "1090" // au-dessus de la couche confettis (1080)
    toast.setAttribute("role", "alert")
    // textContent via createTextNode pour les valeurs dynamiques (badge.name) :
    // évite toute injection HTML si un nom de badge contenait des caractères spéciaux.
    const body = document.createElement("div")
    body.className = "toast-body"
    body.textContent = `🏆 Nouveau badge : ${badge.icon} ${badge.name} !`

    const closeBtn = document.createElement("button")
    closeBtn.type = "button"
    closeBtn.className = "btn-close btn-close-white me-2 m-auto"
    closeBtn.setAttribute("aria-label", "Fermer")
    // Fermeture manuelle au clic (pas de data-bs-dismiss → pas besoin du JS Bootstrap)
    closeBtn.addEventListener("click", () => toast.remove())

    const flex = document.createElement("div")
    flex.className = "d-flex"
    flex.appendChild(body)
    flex.appendChild(closeBtn)
    toast.appendChild(flex)

    document.body.appendChild(toast)

    // Disparition automatique après 5 s (filet : si l'utilisateur ne ferme pas).
    setTimeout(() => toast.remove(), 5000)
  }
}
