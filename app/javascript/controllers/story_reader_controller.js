// ============================================================
// Controller Stimulus — lecture vocale de l'histoire
// ============================================================
// Utilise OpenAI TTS côté serveur + HTML5 Audio API côté client.
// Le texte est envoyé au serveur (POST /stories/:id/audio),
// qui appelle OpenAI et retourne un fichier MP3.
// Le navigateur joue le MP3 via un objet Audio standard.
//
// Plus fiable que Web Speech API (speechSynthesis) qui est instable
// et silencieuse sur certaines configurations Chrome/Mac.
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles déclarées :
  // - "text"     : le div contenant le texte de l'histoire (non utilisé pour TTS ici,
  //                mais conservé pour compatibilité avec story_choice_controller)
  // - "playBtn"  : bouton "Écouter" / "Reprendre"
  // - "pauseBtn" : bouton "Pause"
  // - "stopBtn"  : bouton "Arrêter"
  static targets = ["text", "playBtn", "pauseBtn", "stopBtn"]

  // connect() est appelé automatiquement par Stimulus quand le controller est attaché au DOM
  connect() {
    // L'élément Audio HTML5 qui jouera le MP3 retourné par OpenAI TTS
    this.audio = null

    // URL blob créée depuis le binaire MP3 — on la libère au stop() / disconnect()
    this.audioUrl = null

    // Écoute l'événement déclenché par story_choice_controller quand la continuation
    // interactive est prête — reprend automatiquement la lecture sur le nouveau texte
    this.onContinuationReady = (event) => this.resumeAfterContinuation(event)
    document.addEventListener("story:continuation-ready", this.onContinuationReady)
  }

  // ============================================================
  // play() — lance ou reprend la lecture
  // ============================================================
  // Appelée par data-action="click->story-reader#play"
  async play() {
    // Si un audio est déjà chargé et en pause, on reprend sans rappeler le serveur
    if (this.audio && this.audio.paused && this.audio.currentTime > 0) {
      this.audio.play()
      this.updateButtons(true)
      return
    }

    // Sinon, on demande l'audio de l'histoire complète au serveur
    await this.loadAndPlay("story")
  }

  // ============================================================
  // loadAndPlay(source) — appelle le serveur TTS et joue le MP3
  // ============================================================
  // source : "story" pour l'histoire principale, "continuation" pour la suite interactive
  async loadAndPlay(source) {
    // Indique visuellement que le chargement est en cours
    this.setLoading(true)
    this.updateButtons(true)

    try {
      // Récupère l'ID de l'histoire depuis l'attribut data-story-id du controller
      const storyId = this.element.dataset.storyId

      // Token CSRF obligatoire pour les requêtes POST Rails (protection CSRF)
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      // Appel POST vers /stories/:id/audio
      // Le serveur appelle OpenAI TTS et retourne le MP3 binaire
      const response = await fetch(`/stories/${storyId}/audio`, {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token":  csrfToken
        },
        // Indique au serveur quel texte lire : histoire ou continuation
        body: JSON.stringify({ source })
      })

      // Gestion des erreurs HTTP (500, 503, etc.)
      if (!response.ok) {
        console.error(`story-reader: erreur serveur TTS (${response.status})`)
        this.setLoading(false)
        this.updateButtons(false)
        return
      }

      // Récupère la réponse binaire (MP3) sous forme de Blob
      const blob = await response.blob()

      // Crée une URL temporaire en mémoire pour que l'élément Audio puisse la jouer
      // URL.createObjectURL génère un lien du type "blob:http://..."
      const url = URL.createObjectURL(blob)

      // Libère l'ancienne URL blob si elle existe (évite les fuites mémoire)
      if (this.audioUrl) URL.revokeObjectURL(this.audioUrl)
      this.audioUrl = url

      // Crée un élément Audio standard — fonctionne comme <audio src="...">
      this.audio = new Audio(url)

      // Quand la lecture se termine naturellement, on remet les boutons à l'état initial
      this.audio.onended = () => this.updateButtons(false)

      // En cas d'erreur de lecture (codec, réseau, etc.)
      this.audio.onerror = (e) => {
        console.error("story-reader: erreur lecture audio", e)
        this.updateButtons(false)
      }

      // Tout est prêt — retire le loading et lance la lecture
      this.setLoading(false)
      this.audio.play()

    } catch (error) {
      // Erreur réseau (pas de connexion, timeout, etc.)
      console.error("story-reader: erreur lors de la récupération de l'audio TTS", error)
      this.setLoading(false)
      this.updateButtons(false)
    }
  }

  // ============================================================
  // pause() — met la lecture en pause sans la réinitialiser
  // ============================================================
  // Appelée par data-action="click->story-reader#pause"
  pause() {
    if (this.audio) {
      // HTML5 Audio.pause() mémorise la position — on pourra reprendre avec play()
      this.audio.pause()
      this.updateButtons(false)
    }
  }

  // ============================================================
  // stop() — arrête complètement la lecture et remet à zéro
  // ============================================================
  // Appelée par data-action="click->story-reader#stop"
  stop() {
    if (this.audio) {
      this.audio.pause()
      // currentTime = 0 remet au début — si on reclique Play, ça repart depuis le début
      this.audio.currentTime = 0
      this.updateButtons(false)
    }
  }

  // ============================================================
  // resumeAfterContinuation — lit la continuation interactive
  // ============================================================
  // Appelé via l'événement "story:continuation-ready".
  // Génère et joue uniquement le texte de la continuation,
  // pas toute l'histoire depuis le début.
  async resumeAfterContinuation(event) {
    // Arrête la lecture en cours si nécessaire avant de charger la suite
    if (this.audio) {
      this.audio.pause()
      this.audio.currentTime = 0
    }
    await this.loadAndPlay("continuation")
  }

  // ============================================================
  // disconnect() — nettoyage quand on quitte la page
  // ============================================================
  // Appelé automatiquement par Stimulus lors de la navigation
  disconnect() {
    // Arrête la lecture si l'utilisateur navigue ailleurs
    if (this.audio) {
      this.audio.pause()
      this.audio = null
    }

    // Libère la mémoire allouée par le blob URL
    if (this.audioUrl) {
      URL.revokeObjectURL(this.audioUrl)
      this.audioUrl = null
    }

    // Retire le listener pour éviter les memory leaks
    document.removeEventListener("story:continuation-ready", this.onContinuationReady)
  }

  // ============================================================
  // updateButtons(isPlaying) — synchronise l'état des boutons
  // ============================================================
  // isPlaying : true → lecture en cours, false → lecture arrêtée/en pause
  updateButtons(isPlaying) {
    // Masque le bouton Play quand la lecture est active
    if (this.hasPlayBtnTarget) {
      this.playBtnTarget.classList.toggle("d-none", isPlaying)
    }

    // Masque le bouton Pause quand la lecture est inactive
    if (this.hasPauseBtnTarget) {
      this.pauseBtnTarget.classList.toggle("d-none", !isPlaying)
    }

    // Le bouton Stop reste toujours visible
  }

  // ============================================================
  // setLoading(isLoading) — état de chargement sur le bouton Play
  // ============================================================
  // Pendant que le serveur génère l'audio, on désactive le bouton Play
  // et on change son texte pour indiquer que ça charge
  setLoading(isLoading) {
    if (this.hasPlayBtnTarget) {
      this.playBtnTarget.disabled    = isLoading
      this.playBtnTarget.textContent = isLoading ? "⏳ Chargement..." : "▶ Écouter"
    }
  }
}
