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
    redirect: String,  // URL vers laquelle rediriger quand c'est prêt
    // Messages de progression traduits (passés par la vue via data-…-msgN-value)
    msg1: String,
    msg2: String,
    msg3: String,
    msg4: String
  }

  // Cible facultative : le paragraphe où afficher les messages de progression
  static targets = ["message"]

  connect() {
    // Démarre le polling avec un délai initial de 2 secondes
    // Délai courant en ms — commence à 2s, double à chaque tentative (max 16s)
    this.currentDelay = 2000
    this.scheduleNextPoll()

    // Lance la rotation des messages de progression (réduit la sensation d'attente)
    this.startMessageRotation()
  }

  disconnect() {
    // Annule le prochain poll planifié quand on quitte la page (évite les memory leaks)
    this.stopPolling()
    // Arrête aussi la rotation des messages
    this.stopMessageRotation()
  }

  // ── Rotation des messages de génération ──
  // Fait défiler des messages évocateurs ("L'histoire s'écrit...", etc.) toutes
  // les 3,5s pendant que l'IA travaille — l'attente paraît plus courte qu'avec
  // un simple spinner figé. Purement cosmétique (pas lié au vrai statut serveur).
  startMessageRotation() {
    // Si la vue ne fournit pas de cible "message", on ne fait rien
    if (!this.hasMessageTarget) return

    // Messages affichés successivement, dans l'ordre logique de fabrication
    // (textes traduits fournis par la vue via les data-values)
    this.messages = [
      this.msg1Value,
      this.msg2Value,
      this.msg3Value,
      this.msg4Value
    ]
    this.messageIndex = 0
    this.messageTarget.textContent = this.messages[0] // affiche le 1er tout de suite

    // Toutes les 3,5s : fondu sortant → change le texte → fondu entrant
    this.messageInterval = setInterval(() => {
      this.messageIndex = (this.messageIndex + 1) % this.messages.length
      this.messageTarget.style.opacity = "0"
      setTimeout(() => {
        this.messageTarget.textContent = this.messages[this.messageIndex]
        this.messageTarget.style.opacity = "1"
      }, 300) // doit correspondre à la durée de transition CSS
    }, 3500)
  }

  // Arrête la rotation des messages (appelé à la déconnexion du controller)
  stopMessageRotation() {
    if (this.messageInterval) clearInterval(this.messageInterval)
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

      // Si l'histoire est terminée, on arrête le polling et on redirige
      if (data.completed) {
        this.stopPolling()
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
      this.scheduleNextPoll()

    } catch (error) {
      // En cas d'erreur réseau, on logge et on replanifie quand même
      console.error("StoryStatus: erreur réseau", error)
      this.increaseDelay()
      this.scheduleNextPoll()
    }
  }
}
