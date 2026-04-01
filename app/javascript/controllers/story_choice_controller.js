// ============================================================
// Stimulus Controller : story-choice
// ============================================================
// Gère le choix interactif SANS recharger la page :
//   1. Intercepte le submit du formulaire de choix
//   2. Envoie le choix via fetch (AJAX) → pas de rechargement
//   3. Affiche un spinner "la suite se prépare..."
//   4. Fait du polling sur /stories/:id/status toutes les 2s
//   5. Quand c'est prêt : insère la continuation dans le texte
//   6. Déclenche l'événement "story:continuation-ready" pour
//      que story_reader_controller reprenne la lecture vocale
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // "statusUrl" : URL du endpoint JSON de statut (ex: /stories/1/status)
  static values = { statusUrl: String }

  // ============================================================
  // submit(event) — appelé par data-action="submit->story-choice#submit"
  // ============================================================
  // Intercepte le formulaire avant qu'il ne fasse un rechargement complet
  async submit(event) {
    // Annule la soumission HTML normale (qui rechargerait la page)
    event.preventDefault()

    const form = event.currentTarget

    // Récupère les données du formulaire (chosen_option = "a" ou "b")
    const formData = new FormData(form)

    // Token CSRF obligatoire pour les requêtes POST Rails (sécurité)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Remplace les boutons de choix par un spinner pendant la génération
    this.showLoadingState()

    try {
      // Envoie le choix en JSON — le controller Rails répond avec { success: true }
      await fetch(form.action, {
        method: "POST",
        body: formData,
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        }
      })

      // Démarre le polling pour détecter quand la suite est prête
      this.startPolling()

    } catch (error) {
      console.error("story-choice: erreur lors de l'envoi du choix", error)
      // En cas d'erreur réseau, fallback vers rechargement classique
      window.location.reload()
    }
  }

  // ============================================================
  // Spinner — remplace les boutons pendant la génération
  // ============================================================
  showLoadingState() {
    this.element.innerHTML = `
      <div class="text-center py-5">
        <div class="spinner-border text-primary mb-3" role="status">
          <span class="visually-hidden">Génération en cours...</span>
        </div>
        <p class="text-muted fw-semibold">La suite de l'aventure se prépare... ✨</p>
        <p class="text-muted small">Cela prend généralement 15 à 30 secondes.</p>
      </div>
    `
  }

  // ============================================================
  // Polling — vérifie le statut toutes les 2 secondes
  // ============================================================
  startPolling() {
    this.pollingInterval = setInterval(() => this.checkStatus(), 2000)
  }

  stopPolling() {
    if (this.pollingInterval) clearInterval(this.pollingInterval)
  }

  async checkStatus() {
    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) return

      const data = await response.json()

      if (data.completed) {
        // La suite est prête — on arrête le polling et on met à jour le DOM
        this.stopPolling()
        this.appendContinuation(data.continuation)
      }

      if (data.status === "failed") {
        // Erreur de génération — recharge la page pour afficher le message d'erreur
        this.stopPolling()
        window.location.reload()
      }

    } catch (error) {
      console.error("story-choice: erreur de polling", error)
    }
  }

  // ============================================================
  // appendContinuation — insère la suite dans la page
  // ============================================================
  appendContinuation(continuationHtml) {
    // Supprime la card de choix (ce composant) du DOM
    this.element.remove()

    if (!continuationHtml) return

    // Trouve le div qui contient le texte de l'histoire
    // (data-story-reader-target="text" dans show.html.erb)
    const storyContent = document.querySelector('[data-story-reader-target="text"]')
    if (!storyContent) return

    // Le HTML est déjà généré côté serveur par Redcarpet (stories#status)
    // On l'insère directement sans parser le markdown en JS
    storyContent.insertAdjacentHTML("beforeend", `
      <div class="story-continuation-divider">✦ ✦ ✦</div>
      ${continuationHtml}
    `)

    // Déclenche l'événement personnalisé avec le HTML de la continuation
    // story_reader_controller extrait le texte brut depuis innerText pour la lecture vocale
    document.dispatchEvent(new CustomEvent("story:continuation-ready", {
      detail: { html: continuationHtml }
    }))
  }

  // Arrête le polling si l'utilisateur quitte la page
  disconnect() {
    this.stopPolling()
  }
}
