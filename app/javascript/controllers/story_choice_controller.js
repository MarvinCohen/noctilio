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
  // loadingSr / loadingTitle / loadingHint : textes traduits du spinner (i18n)
  static values = {
    statusUrl:    String,
    loadingSr:    String,
    loadingTitle: String,
    loadingHint:  String
  }

  // ============================================================
  // submit(event) — appelé par data-action="submit->story-choice#submit"
  // ============================================================
  // Intercepte le formulaire avant qu'il ne fasse un rechargement complet
  async submit(event) {
    // Annule la soumission HTML normale (qui rechargerait la page)
    event.preventDefault()

    // Retour haptique : petite vibration (15 ms) pour confirmer le choix au toucher,
    // comme un bouton d'app native. On respecte "réduire les animations" (prefers-reduced-motion)
    // et on vérifie que navigator.vibrate existe (absent sur iOS Safari → ignoré sans erreur).
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches &&
        typeof navigator.vibrate === "function") {
      navigator.vibrate(15)
    }

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
    // Spinner doré .story-spinner (au lieu du spinner Bootstrap bleu) pour rester
    // dans la palette nocturne de Noctilio (voir _story_show.scss).
    this.element.innerHTML = `
      <div class="text-center py-5">
        <div class="story-spinner mb-3" role="status">
          <span class="visually-hidden">${this.loadingSrValue}</span>
        </div>
        <p class="story-generating-message">${this.loadingTitleValue}</p>
        <p class="story-generating-hint">${this.loadingHintValue}</p>
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
        // La suite est prête — on arrête le polling et on met à jour le DOM.
        // On transmet : le texte, l'illustration de la suite, le HTML du prochain
        // choix, et choice_id + audio pour que le lecteur enchaîne (Partie B).
        this.stopPolling()
        this.appendContinuation(data)
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
  // data : payload JSON de stories#status. On en lit :
  //   - continuation                  : HTML du texte de la suite
  //   - continuation_illustration_url : image du moment fort de CETTE suite
  //   - next_choice_html              : formulaire du PROCHAIN choix (ou null si fin)
  //   - choice_id / continuation_audio_url : pour l'enchaînement audio (Partie B)
  appendContinuation(data) {
    const continuationHtml = data.continuation
    const illustrationUrl  = data.continuation_illustration_url
    const nextChoiceHtml   = data.next_choice_html
    const choiceId         = data.choice_id
    const audioUrl         = data.continuation_audio_url

    // Supprime la card de choix (ce composant) du DOM
    this.element.remove()

    if (!continuationHtml) return

    // Trouve le div qui contient le texte de l'histoire
    // (data-story-reader-target="text" dans show.html.erb)
    const storyContent = document.querySelector('[data-story-reader-target="text"]')
    if (!storyContent) return

    // ── Illustration de la suite ──
    // Si une image est attachée au choix, on l'insère AU-DESSUS du texte de la suite,
    // comme la couverture au-dessus de l'histoire initiale. onerror → on retire l'image
    // cassée (404 blob orphelin) au lieu d'afficher l'icône brisée du navigateur.
    let illustrationBlock = ""
    if (illustrationUrl) {
      illustrationBlock = `
        <div class="story-continuation-illustration mb-3">
          <img src="${illustrationUrl}" alt=""
               loading="lazy"
               style="width:100%;border-radius:14px;display:block;"
               onerror="this.closest('.story-continuation-illustration').remove()">
        </div>
      `
    }

    // Le HTML du texte est déjà généré côté serveur (render_story_markdown).
    // On insère : séparateur ✦, illustration (si présente), puis le texte.
    storyContent.insertAdjacentHTML("beforeend", `
      <div class="story-continuation-divider">✦ ✦ ✦</div>
      ${illustrationBlock}
      ${continuationHtml}
    `)

    // ── Prochain choix ──
    // Si la suite proposait un nouveau dilemme, le serveur a rendu son formulaire.
    // On l'insère après le texte : Stimulus reconnecte un story-choice neuf →
    // boutons cliquables + nouveau polling. Sinon (fin de l'histoire) on n'ajoute rien.
    if (nextChoiceHtml) {
      storyContent.insertAdjacentHTML("beforeend", nextChoiceHtml)
    }

    // Déclenche l'événement personnalisé avec le HTML de la continuation.
    // On joint choiceId + audioUrl : le lecteur audio (story_reader_controller)
    // enchaîne sur l'audio de la suite quand le passage en cours est terminé.
    //   - audioUrl présent → la suite est déjà prête, lecture directe
    //   - audioUrl null    → le lecteur demandera l'audio via choiceId (202 + polling)
    document.dispatchEvent(new CustomEvent("story:continuation-ready", {
      detail: { html: continuationHtml, choiceId: choiceId, audioUrl: audioUrl }
    }))
  }

  // Arrête le polling si l'utilisateur quitte la page
  disconnect() {
    this.stopPolling()
  }
}
