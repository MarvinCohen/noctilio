// ============================================================
// Controller Stimulus — chargement asynchrone de l'illustration
// ============================================================
// Quand l'histoire est terminée mais que l'image n'est pas encore
// générée, ce controller poll /stories/:id/status toutes les 3s
// et affiche l'image dès qu'elle est disponible.
//
// Cela permet d'afficher la page de lecture immédiatement après
// la génération du texte, sans attendre l'image (qui peut prendre
// 5-15s avec fal.ai ou DALL-E 3).
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // "statusUrl" : URL du endpoint JSON de statut (ex: /stories/1/status)
  // "alt"       : texte alternatif pour l'image (accessibilité)
  static values = { statusUrl: String, alt: String }

  // connect() est appelé automatiquement par Stimulus quand le controller est attaché au DOM
  connect() {
    // Compteur de tentatives — évite de poller indéfiniment si l'image échoue
    this.attempts = 0
    // Lance le polling immédiatement
    this.startPolling()
  }

  // ============================================================
  // startPolling() — vérifie la disponibilité de l'image toutes les 3s
  // ============================================================
  startPolling() {
    // Intervalle de 3 secondes — assez court pour une bonne UX, assez long pour ne pas surcharger
    this.pollingInterval = setInterval(() => this.checkImage(), 3000)
  }

  stopPolling() {
    if (this.pollingInterval) clearInterval(this.pollingInterval)
  }

  // ============================================================
  // checkImage() — requête JSON vers /stories/:id/status
  // ============================================================
  async checkImage() {
    // Limite à 40 tentatives (40 × 3s = 2 minutes max)
    // Si l'image n'est pas là après 2 minutes, on arrête le spinner
    this.attempts++
    if (this.attempts > 40) {
      this.stopPolling()
      const skeleton = this.element.querySelector(".story-illustration-skeleton")
      if (skeleton) skeleton.style.display = "none"
      return
    }

    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) return

      const data = await response.json()

      // Si l'image est disponible, on l'affiche et on arrête le polling
      if (data.image_url) {
        this.stopPolling()
        this.displayImage(data.image_url)
      }

    } catch (error) {
      // Erreur réseau — on continue à poller sans crasher
      console.error("story-image: erreur de polling", error)
    }
  }

  // ============================================================
  // displayImage(url) — insère et affiche l'image dans le DOM
  // ============================================================
  displayImage(url) {
    // Récupère le skeleton (indicateur de chargement) pour le masquer après
    const skeleton = this.element.querySelector(".story-illustration-skeleton")

    // Crée un élément <img> et le configure
    const img = document.createElement("img")
    img.src       = url
    img.alt       = this.altValue || "Illustration de l'histoire"
    img.className = "story-illustration-img"

    // L'image est cachée jusqu'à ce qu'elle soit complètement chargée
    // (évite l'effet de flash avec une image partiellement rendue)
    img.style.display = "none"

    // Quand l'image est chargée : affiche l'image, masque le skeleton
    img.onload = () => {
      img.style.display = "block"
      if (skeleton) skeleton.style.display = "none"
    }

    // En cas d'erreur de chargement (URL cassée, 404, etc.) — affiche un message
    img.onerror = () => {
      if (skeleton) skeleton.innerHTML = "<p style=\"color:#777;font-size:0.8rem;\">Illustration non disponible</p>"
    }

    // Ajoute l'image dans le wrapper (ce controller)
    this.element.appendChild(img)
  }

  // disconnect() — arrête le polling si l'utilisateur quitte la page
  disconnect() {
    this.stopPolling()
  }
}
