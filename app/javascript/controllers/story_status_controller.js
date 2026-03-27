// ============================================================
// Stimulus Controller : story-status
// ============================================================
// Vérifie toutes les 2 secondes si l'histoire a fini de se générer.
// Quand le statut est "completed", redirige vers la page de lecture.
//
// Utilisation dans la vue (data-controller="story-status") :
//   data-story-status-url-value="/stories/1/status"
//   data-story-status-redirect-value="/stories/1"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Déclare les "values" — attributs data- récupérés automatiquement
  static values = {
    url: String,       // URL du endpoint JSON de statut
    redirect: String   // URL vers laquelle rediriger quand c'est prêt
  }

  connect() {
    // Démarre le polling toutes les 2 secondes quand le controller est monté
    console.log("StoryStatus: démarrage du polling...")
    this.startPolling()
  }

  disconnect() {
    // Arrête le polling quand on quitte la page (évite les memory leaks)
    this.stopPolling()
  }

  startPolling() {
    // setInterval exécute checkStatus toutes les 2000ms (2 secondes)
    this.pollingInterval = setInterval(() => {
      this.checkStatus()
    }, 2000)
  }

  stopPolling() {
    // clearInterval annule le setInterval en cours
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
    }
  }

  async checkStatus() {
    try {
      // Appelle le endpoint /stories/:id/status qui retourne du JSON
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "application/json",
          // Inclut le token CSRF pour les requêtes Rails
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })

      if (!response.ok) {
        console.error("StoryStatus: erreur HTTP", response.status)
        return
      }

      const data = await response.json()
      console.log("StoryStatus:", data.status)

      // Si l'histoire est terminée, on arrête le polling et on redirige
      if (data.completed) {
        this.stopPolling()
        console.log("StoryStatus: histoire prête ! Redirection...")
        window.location.href = this.redirectValue
      }

      // Si la génération a échoué, on recharge la page pour afficher l'erreur
      if (data.status === "failed") {
        this.stopPolling()
        window.location.reload()
      }

    } catch (error) {
      // En cas d'erreur réseau, on logge mais on continue le polling
      console.error("StoryStatus: erreur réseau", error)
    }
  }
}
