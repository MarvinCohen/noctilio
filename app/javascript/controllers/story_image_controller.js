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
  // "statusUrl"   : URL du endpoint JSON de statut (ex: /stories/1/status)
  // "alt"         : texte alternatif pour l'image (accessibilité)
  // "unavailable" : message affiché si l'image ne peut pas se charger (i18n)
  static values = { statusUrl: String, alt: String, unavailable: String }

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
  // displayImage(url, retry) — insère et affiche l'image dans le DOM
  // ============================================================
  // retry : compteur de re-tentatives en cas d'échec de chargement.
  //   L'image vient d'être uploadée sur Cloudinary, qui met parfois quelques
  //   secondes à la rendre livrable. Le tout premier chargement peut donc
  //   renvoyer un 404 transitoire alors que le blob est déjà attaché côté serveur.
  //   Sans re-tentative, on afficherait "Illustration non disponible" à tort et
  //   l'utilisateur devrait recharger la page à la main pour voir l'image.
  displayImage(url, retry = 0) {
    // Récupère le skeleton (indicateur de chargement) pour le masquer après
    const skeleton = this.element.querySelector(".story-illustration-skeleton")

    // Crée un élément <img> et le configure
    const img = document.createElement("img")
    img.src       = url
    img.alt       = this.altValue
    img.className = "story-illustration-img"

    // L'image est cachée jusqu'à ce qu'elle soit complètement chargée
    // (évite l'effet de flash avec une image partiellement rendue)
    img.style.display = "none"

    // Quand l'image est chargée : affiche l'image, masque le skeleton
    img.onload = () => {
      img.style.display = "block"
      if (skeleton) skeleton.style.display = "none"
    }

    // En cas d'erreur de chargement : on réessaie quelques fois (404 transitoire
    // Cloudinary) avant d'abandonner. On retire l'<img> échouée et on relance
    // displayImage après 2s — le skeleton "chargement" reste visible entre-temps.
    img.onerror = () => {
      img.remove()
      if (retry < 5) {
        // Nouvelle tentative — l'image est probablement encore en cours de
        // traitement côté Cloudinary, elle sera livrable dans quelques secondes.
        setTimeout(() => this.displayImage(url, retry + 1), 2000)
      } else if (skeleton) {
        // 5 échecs (~10s) : on abandonne et on affiche le message discret.
        skeleton.innerHTML = `<p style="color:#777;font-size:0.8rem;">${this.unavailableValue}</p>`
      }
    }

    // Ajoute l'image dans le wrapper (ce controller)
    this.element.appendChild(img)
  }

  // disconnect() — arrête le polling si l'utilisateur quitte la page
  disconnect() {
    this.stopPolling()
  }
}
