// ============================================================
// Controller Stimulus — lecteur audio sticky
// ============================================================
// Utilise OpenAI TTS côté serveur + HTML5 Audio API côté client.
// Affiche un lecteur fixe à droite de la page avec :
//   - Bouton Play / Pause / Stop
//   - Barre de progression cliquable
//   - Timer temps écoulé / durée totale
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles déclarées :
  // - "text"        : div du contenu de l'histoire (utilisé par story_choice_controller)
  // - "playBtn"     : bouton play / reprendre
  // - "pauseBtn"    : bouton pause (masqué par défaut)
  // - "stopBtn"     : bouton stop
  // - "progressBar" : barre de progression (div intérieure qui s'élargit)
  // - "track"       : barre de progression cliquable (conteneur)
  // - "currentTime" : span temps écoulé (ex: "1:23")
  // - "totalTime"   : span durée totale (ex: "6:12")
  static targets = ["text", "playBtn", "pauseBtn", "stopBtn", "progressBar", "track", "currentTime", "totalTime"]

  connect() {
    // Objet Audio HTML5 courant
    this.audio = null

    // URL blob du MP3 — libérée à stop() / disconnect()
    this.audioUrl = null

    // Indique si l'utilisateur était en train d'écouter (pour la continuation)
    this.playing = false

    // Écoute la continuation interactive pour reprendre la lecture si elle était active
    this.onContinuationReady = (event) => this.resumeAfterContinuation(event)
    document.addEventListener("story:continuation-ready", this.onContinuationReady)
  }

  // ============================================================
  // play() — lance ou reprend la lecture
  // ============================================================
  async play() {
    // Si l'audio est en pause (pas à 0), on reprend sans rappeler le serveur
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
  async loadAndPlay(source) {
    this.setLoading(true)
    this.updateButtons(true)

    try {
      const storyId   = this.element.dataset.storyId
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch(`/stories/${storyId}/audio`, {
        method:  "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
        body:    JSON.stringify({ source })
      })

      if (!response.ok) {
        console.error(`story-reader: erreur serveur TTS (${response.status})`)
        this.setLoading(false)
        this.updateButtons(false)
        return
      }

      const blob = await response.blob()

      // Libère l'ancienne URL blob avant d'en créer une nouvelle
      if (this.audioUrl) URL.revokeObjectURL(this.audioUrl)
      this.audioUrl = URL.createObjectURL(blob)

      this.audio = new Audio(this.audioUrl)

      // Quand les métadonnées sont chargées : affiche la durée totale
      this.audio.addEventListener("loadedmetadata", () => {
        if (this.hasTotalTimeTarget) {
          this.totalTimeTarget.textContent = this.formatTime(this.audio.duration)
        }
      })

      // Mise à jour de la barre de progression et du timer à chaque seconde
      this.audio.addEventListener("timeupdate", () => this.updateProgress())

      // Fin de la lecture
      this.audio.onended = () => {
        this.updateButtons(false)
        this.resetProgress()
      }

      // Erreur de lecture
      this.audio.onerror = (e) => {
        console.error("story-reader: erreur lecture audio", e)
        this.updateButtons(false)
      }

      this.setLoading(false)
      this.audio.play()

    } catch (error) {
      console.error("story-reader: erreur lors de la récupération de l'audio TTS", error)
      this.setLoading(false)
      this.updateButtons(false)
    }
  }

  // ============================================================
  // pause() — met en pause
  // ============================================================
  pause() {
    if (this.audio) {
      this.audio.pause()
      this.updateButtons(false)
    }
  }

  // ============================================================
  // stop() — arrête et remet à zéro
  // ============================================================
  stop() {
    if (this.audio) {
      this.audio.pause()
      this.audio.currentTime = 0
      this.updateButtons(false)
      this.resetProgress()
    }
  }

  // ============================================================
  // seek(event) — clic sur la barre pour naviguer dans l'audio
  // ============================================================
  seek(event) {
    if (!this.audio || !this.audio.duration) return

    // Calcule la position relative du clic (0 → 1) sur la barre
    const track    = event.currentTarget
    const rect     = track.getBoundingClientRect()
    const ratio    = (event.clientX - rect.left) / rect.width
    const clamped  = Math.max(0, Math.min(1, ratio))

    // Déplace la lecture à la position cliquée
    this.audio.currentTime = clamped * this.audio.duration
  }

  // ============================================================
  // resumeAfterContinuation — reprend après un choix interactif
  // ============================================================
  async resumeAfterContinuation(event) {
    // Ne lance la lecture que si l'utilisateur écoutait déjà
    if (!this.playing) return

    if (this.audio) {
      this.audio.pause()
      this.audio.currentTime = 0
    }
    await this.loadAndPlay("continuation")
  }

  // ============================================================
  // disconnect() — nettoyage en quittant la page
  // ============================================================
  disconnect() {
    if (this.audio) {
      this.audio.pause()
      this.audio = null
    }
    if (this.audioUrl) {
      URL.revokeObjectURL(this.audioUrl)
      this.audioUrl = null
    }
    document.removeEventListener("story:continuation-ready", this.onContinuationReady)
  }

  // ============================================================
  // updateProgress() — met à jour la barre et le timer
  // ============================================================
  updateProgress() {
    if (!this.audio || !this.audio.duration) return

    const ratio = this.audio.currentTime / this.audio.duration

    // Largeur de la barre en pourcentage
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${ratio * 100}%`
    }

    // Temps écoulé affiché
    if (this.hasCurrentTimeTarget) {
      this.currentTimeTarget.textContent = this.formatTime(this.audio.currentTime)
    }
  }

  // ============================================================
  // resetProgress() — remet la barre et le timer à zéro
  // ============================================================
  resetProgress() {
    if (this.hasProgressBarTarget)  this.progressBarTarget.style.width = "0%"
    if (this.hasCurrentTimeTarget)  this.currentTimeTarget.textContent  = "0:00"
    if (this.hasTotalTimeTarget)    this.totalTimeTarget.textContent    = "--:--"
  }

  // ============================================================
  // updateButtons(isPlaying) — synchronise l'état des boutons
  // ============================================================
  updateButtons(isPlaying) {
    this.playing = isPlaying

    if (this.hasPlayBtnTarget)  this.playBtnTarget.classList.toggle("d-none", isPlaying)
    if (this.hasPauseBtnTarget) this.pauseBtnTarget.classList.toggle("d-none", !isPlaying)
  }

  // ============================================================
  // setLoading(isLoading) — état chargement sur le bouton Play
  // ============================================================
  setLoading(isLoading) {
    if (this.hasPlayBtnTarget) {
      this.playBtnTarget.disabled    = isLoading
      this.playBtnTarget.textContent = isLoading ? "⏳" : "▶"
    }
  }

  // ============================================================
  // formatTime(seconds) — convertit des secondes en "M:SS"
  // ============================================================
  formatTime(seconds) {
    if (!seconds || isNaN(seconds)) return "0:00"
    const m = Math.floor(seconds / 60)
    const s = Math.floor(seconds % 60).toString().padStart(2, "0")
    return `${m}:${s}`
  }
}
