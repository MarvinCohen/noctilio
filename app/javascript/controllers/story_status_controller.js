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
    // Démarre le polling avec un délai initial de 2 secondes
    console.log("StoryStatus: démarrage du polling...")
    // Délai courant en ms — commence à 2s, double à chaque tentative (max 16s)
    this.currentDelay = 2000
    this.scheduleNextPoll()
  }

  disconnect() {
    // Annule le prochain poll planifié quand on quitte la page (évite les memory leaks)
    this.stopPolling()
  }

  // Planifie le prochain poll avec le délai courant (backoff exponentiel)
  // Plus l'attente dure, moins on interroge souvent le serveur
  scheduleNextPoll() {
    this.pollingTimeout = setTimeout(() => {
      this.checkStatus()
    }, this.currentDelay)
  }

  // Augmente le délai entre chaque poll : 2s → 4s → 8s → 16s max
  // Économise les ressources serveur si la génération prend du temps
  increaseDelay() {
    const MAX_DELAY = 16000 // Plafond à 16 secondes
    this.currentDelay = Math.min(this.currentDelay * 2, MAX_DELAY)
  }

  startPolling() {
    this.scheduleNextPoll()
  }

  stopPolling() {
    // clearTimeout annule le poll planifié en cours
    if (this.pollingTimeout) {
      clearTimeout(this.pollingTimeout)
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
        return
      }

      // Si la génération a échoué, on recharge pour afficher le message d'erreur
      if (data.status === "failed") {
        this.stopPolling()
        window.location.reload()
        return
      }

      // Histoire encore en cours : augmente le délai et planifie le prochain poll
      // Backoff exponentiel : 2s → 4s → 8s → 16s max
      this.increaseDelay()
      console.log(`StoryStatus: ${data.status} — prochain poll dans ${this.currentDelay / 1000}s`)
      this.scheduleNextPoll()

    } catch (error) {
      // En cas d'erreur réseau, on logge et on replanifie quand même
      console.error("StoryStatus: erreur réseau", error)
      this.increaseDelay()
      this.scheduleNextPoll()
    }
  }
}
