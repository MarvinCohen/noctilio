// ============================================================
// Controller Stimulus — lecteur audio flottant (FAB)
// ============================================================
// Utilise OpenAI TTS côté serveur + HTML5 Audio API côté client.
// Affiche un bouton flottant rond en bas à droite avec :
//   - Anneau de progression qui se remplit pendant la lecture
//   - Au clic : déplie une barre complète (Play / Pause, barre, timers)
//   - Bulle "écoulé / total" quand le lecteur est replié
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles déclarées :
  // - "text"        : div du contenu de l'histoire (utilisé par story_choice_controller)
  // - "fab"         : bouton flottant rond (état replié) — déplie + lance la lecture
  // - "ring"        : cercle SVG de progression autour du FAB (anneau doré)
  // - "bubble"      : bulle "0:00 / 3:20" affichée pendant la lecture (lecteur replié)
  // - "playBtn"     : bouton play / reprendre (dans le panneau déplié)
  // - "pauseBtn"    : bouton pause (masqué par défaut)
  // - "progressBar" : barre de progression (div intérieure qui s'élargit)
  // - "track"       : barre de progression cliquable (conteneur)
  // - "currentTime" : span temps écoulé (ex: "1:23")
  // - "totalTime"   : span durée totale (ex: "6:12")
  static targets = ["text", "fab", "ring", "bubble", "playBtn", "pauseBtn", "progressBar", "track", "currentTime", "totalTime", "preparingBadge"]

  // Circonférence de l'anneau de progression : 2 × π × r (r = 26 dans le SVG).
  // Sert à calculer le stroke-dashoffset qui remplit l'anneau (0 → vide, plein → 0).
  RING_CIRC = 163.4

  connect() {
    // Objet Audio HTML5 courant
    this.audio = null

    // URL blob du MP3 — libérée à stop() / disconnect()
    this.audioUrl = null

    // Indique si l'utilisateur était en train d'écouter (pour la continuation)
    this.playing = false

    // Suite interactive en attente de lecture après un choix : { choiceId, audioUrl }.
    // Tant qu'elle est définie, le prochain Play joue la SUITE (et non un retour
    // au début de l'histoire). Remise à null une fois la suite jouée.
    this.pendingContinuation = null

    // Intervalle du pré-polling (stocké pour pouvoir l'arrêter)
    this.preCheckInterval = null

    // Intervalle du polling de l'audio de la SUITE (quand l'enfant n'écoute pas
    // au moment du choix). Stocké pour pouvoir l'arrêter en quittant la page.
    this.continuationCheckInterval = null

    // Écoute la continuation interactive pour reprendre la lecture si elle était active
    this.onContinuationReady = (event) => this.resumeAfterContinuation(event)
    document.addEventListener("story:continuation-ready", this.onContinuationReady)

    // Le badge "En préparation" est toujours dans le DOM, mais masqué (d-none) si
    // l'audio principal est déjà prêt. On ne lance le pré-polling QUE s'il est visible
    // (audio principal pas encore généré), sinon on pulserait à tort à chaque chargement.
    if (this.hasPreparingBadgeTarget && !this.preparingBadgeTarget.classList.contains("d-none")) {
      this.startPreCheck()
    }
  }

  // ============================================================
  // startPreCheck — poll /status en arrière-plan dès l'arrivée
  // ============================================================
  // N'attend pas que l'utilisateur clique sur Play — détecte la disponibilité
  // de l'audio dès que GenerateAudioJob termine (~25s après création).
  startPreCheck() {
    const storyId    = this.element.dataset.storyId
    const maxChecks  = 40   // 40 × 3s = 2 minutes max
    let   checkCount = 0

    this.preCheckInterval = setInterval(async () => {
      checkCount++

      try {
        const response = await fetch(`/stories/${storyId}/status`, {
          headers: { "Accept": "application/json" }
        })
        if (!response.ok) return

        const data = await response.json()

        if (data.audio_url) {
          // Audio prêt — on arrête le polling et on signale visuellement
          clearInterval(this.preCheckInterval)
          this.preCheckInterval = null
          this.markReady()
        } else if (checkCount >= maxChecks) {
          // Timeout — on arrête silencieusement, l'utilisateur peut toujours cliquer
          clearInterval(this.preCheckInterval)
          this.preCheckInterval = null
        }
      } catch (e) {
        // Erreur réseau — on continue à poller sans crasher
      }
    }, 3000)
  }

  // ============================================================
  // markReady — signale visuellement que l'audio est prêt
  // ============================================================
  // Cache le badge "En préparation" et déclenche une animation
  // dorée sur le bouton Play pour attirer l'attention.
  markReady() {
    // Cache le badge "En préparation..."
    if (this.hasPreparingBadgeTarget) {
      this.preparingBadgeTarget.classList.add("d-none")
    }

    // Pulse doré PERSISTANT sur le bouton flottant jusqu'à ce que l'enfant clique.
    // (avant : 3 pulses de 0,75s puis retrait — trop court, souvent manqué)
    // Le pulse est retiré au premier clic (voir clearContinuationPulse).
    if (this.hasFabTarget) {
      this.fabTarget.classList.add("audio-fab-btn--ready-loop")
    }
  }

  // ============================================================
  // expandAndPlay() — déplie le lecteur et lance la lecture
  // ============================================================
  // Clic sur le bouton flottant : on déplie la barre complète puis on joue.
  // Si l'audio joue déjà (panneau replié pendant la lecture), on ne fait que
  // déplier — sinon play() relancerait l'histoire depuis le début.
  expandAndPlay() {
    this.element.classList.add("expanded")
    if (this.audio && !this.audio.paused) return
    this.play()
  }

  // ============================================================
  // collapse() — replie le lecteur (la lecture continue en fond)
  // ============================================================
  collapse() {
    this.element.classList.remove("expanded")
  }

  // ============================================================
  // play() — lance ou reprend la lecture
  // ============================================================
  async play() {
    // Premier clic : on retire le pulse doré "prêt" (audio principal ou suite),
    // devenu inutile une fois que l'enfant a déclenché la lecture.
    this.clearContinuationPulse()

    // Reprise d'un passage mis en pause AVANT sa fin → on reprend là où on était.
    // (on exclut le cas "terminé" : currentTime === duration, sinon on ne relancerait rien)
    if (this.audio && this.audio.paused && this.audio.currentTime > 0 && !this.audio.ended) {
      this.audio.play()
      this.updateButtons(true)
      return
    }

    // Une suite est en attente (l'enfant a fait un choix) → on joue la SUITE,
    // jamais un retour au début de l'histoire.
    if (this.pendingContinuation) {
      const { choiceId, audioUrl } = this.pendingContinuation
      this.pendingContinuation = null
      if (audioUrl) {
        this.updateButtons(true)
        this.playFromUrl(audioUrl)
      } else {
        await this.loadAndPlay("continuation", choiceId)
      }
      return
    }

    // Sinon, on demande l'audio de l'histoire complète au serveur (depuis le début)
    await this.loadAndPlay("story")
  }

  // ============================================================
  // loadAndPlay(source, choiceId) — récupère l'audio et le joue
  // ============================================================
  // Si le serveur retourne 200 avec une redirection : joue directement l'URL
  // Si le serveur retourne 202 (génération en cours) : poll /status jusqu'à l'URL
  // choiceId est fourni pour la SUITE interactive (source = "continuation").
  async loadAndPlay(source, choiceId = null) {
    this.setLoading(true)
    this.updateButtons(true)

    try {
      const storyId   = this.element.dataset.storyId
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch(`/stories/${storyId}/audio`, {
        method:  "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
        body:    JSON.stringify({ source, choice_id: choiceId })
      })

      if (response.status === 202) {
        // Audio pas encore prêt — poll le status jusqu'à ce que l'URL apparaisse.
        // On passe la source pour lire le bon champ (audio_url vs continuation_audio_url).
        await this.pollForAudio(storyId, source)
        return
      }

      if (!response.ok) {
        console.error(`story-reader: erreur serveur TTS (${response.status})`)
        this.setLoading(false)
        this.updateButtons(false)
        return
      }

      // 200 avec redirection suivie automatiquement par fetch → joue l'URL finale
      const audioSrc = response.url
      this.playFromUrl(audioSrc)

    } catch (error) {
      console.error("story-reader: erreur lors de la récupération de l'audio TTS", error)
      this.setLoading(false)
      this.updateButtons(false)
    }
  }

  // ============================================================
  // pollForAudio — poll /status toutes les 3s jusqu'à l'URL audio
  // ============================================================
  // source décide quel champ on attend dans la réponse :
  //   - "continuation" → continuation_audio_url (audio de la suite)
  //   - sinon          → audio_url (audio principal de l'histoire)
  async pollForAudio(storyId, source = "story") {
    const maxAttempts = 30  // 30 × 3s = 90s max d'attente
    let   attempts    = 0

    const interval = setInterval(async () => {
      attempts++

      try {
        const response = await fetch(`/stories/${storyId}/status`, {
          headers: { "Accept": "application/json" }
        })
        const data = await response.json()

        // Choisit le bon champ selon la source demandée
        const audioUrl = source === "continuation" ? data.continuation_audio_url : data.audio_url

        if (audioUrl) {
          clearInterval(interval)
          this.playFromUrl(audioUrl)
        } else if (attempts >= maxAttempts) {
          // Timeout — on abandonne
          clearInterval(interval)
          this.setLoading(false)
          this.updateButtons(false)
          console.error("story-reader: timeout en attente de l'audio")
        }
      } catch (e) {
        console.error("story-reader: erreur polling audio", e)
      }
    }, 3000)
  }

  // ============================================================
  // playFromUrl — initialise et joue l'Audio depuis une URL
  // ============================================================
  playFromUrl(url) {
    this.audio = new Audio(url)

    // Durée totale dès que les métadonnées sont chargées
    this.audio.addEventListener("loadedmetadata", () => {
      const total = this.formatTime(this.audio.duration)
      if (this.hasTotalTimeTarget) this.totalTimeTarget.textContent = total
      // Renseigne la durée dans la bulle dès le départ ("0:00 / 3:20")
      if (this.hasBubbleTarget) this.bubbleTarget.textContent = `0:00 / ${total}`
    })

    // Progression à chaque seconde
    this.audio.addEventListener("timeupdate", () => this.updateProgress())

    // Fin de lecture
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
  // resumeAfterContinuation — enchaîne après un choix interactif
  // ============================================================
  // Principe (Partie B) : on NE COUPE PAS le passage en cours et on ne repart
  // jamais au début. On laisse FINIR le passage que l'enfant écoute, puis on
  // enchaîne sur l'audio de la SUITE (la nouvelle partie seulement).
  // Si rien ne joue (l'enfant n'écoutait pas), on ne lance rien.
  resumeAfterContinuation(event) {
    // Détails transmis par story_choice_controller via l'événement
    const choiceId = event.detail?.choiceId
    const audioUrl = event.detail?.audioUrl

    // On mémorise la suite : le prochain Play jouera la SUITE, jamais un retour
    // au début de l'histoire (corrige le bug "le lecteur recommence au début").
    this.pendingContinuation = { choiceId, audioUrl }

    // L'enfant écoutait-il au moment du choix ?
    const listening = this.audio && !this.audio.paused

    if (!audioUrl) {
      // Audio de la suite pas encore généré → chargement visuel ("En préparation")
      // et surveillance de /status. Quand prêt : on cache le badge, et si l'enfant
      // n'écoute pas, on pulse le bouton Play.
      this.showPreparing()
      this.watchContinuationReady(listening)
    } else if (!listening) {
      // Déjà pré-généré et l'enfant n'écoute pas → pulse immédiat
      this.markContinuationReady()
    }

    // Rien ne joue → l'enfant n'écoutait pas : la suite sera jouée au prochain Play.
    if (!listening) return

    // L'enfant écoute : on NE COUPE PAS. On laisse finir le passage en cours, puis
    // on enchaîne automatiquement sur la suite via l'événement onended.
    this.audio.onended = () => {
      this.resetProgress()
      // On relit l'URL depuis pendingContinuation : watchContinuationReady a pu la
      // renseigner entre-temps si l'audio est devenu prêt pendant l'écoute.
      const pending = this.pendingContinuation
      this.pendingContinuation = null
      this.hidePreparing()

      if (pending && pending.audioUrl) {
        // L'audio de la suite est prêt (pré-généré ou détecté pendant l'écoute)
        this.playFromUrl(pending.audioUrl)
      } else {
        // Pas encore prêt → on le demande via le choix (202 + polling sur /status)
        this.loadAndPlay("continuation", choiceId)
      }
    }
  }

  // ============================================================
  // showPreparing / hidePreparing — chargement visuel "En préparation"
  // ============================================================
  showPreparing() {
    if (this.hasPreparingBadgeTarget) this.preparingBadgeTarget.classList.remove("d-none")
  }

  hidePreparing() {
    if (this.hasPreparingBadgeTarget) this.preparingBadgeTarget.classList.add("d-none")
  }

  // ============================================================
  // markContinuationReady — pulse en boucle sur Play (suite prête)
  // ============================================================
  // Variante "boucle infinie" du pulse : plus voyante que markReady (3 anneaux),
  // car la suite peut arriver pendant que l'enfant lit le texte sans écouter.
  // Le pulse s'arrête au clic sur Play (voir clearContinuationPulse dans play()).
  markContinuationReady() {
    if (this.hasFabTarget) {
      this.fabTarget.classList.add("audio-fab-btn--ready-loop")
    }
  }

  // ============================================================
  // clearContinuationPulse — retire le pulse "suite prête"
  // ============================================================
  clearContinuationPulse() {
    if (this.hasFabTarget) {
      this.fabTarget.classList.remove("audio-fab-btn--ready-loop")
    }
  }

  // ============================================================
  // watchContinuationReady — poll /status jusqu'à l'audio de la suite
  // ============================================================
  // Utilisé quand l'enfant n'écoutait pas au moment du choix et que l'audio
  // de la suite n'est pas encore généré. Dès qu'il l'est, on mémorise son URL
  // (pour un clic Play instantané) et on déclenche le pulse.
  watchContinuationReady(listening = false) {
    const storyId    = this.element.dataset.storyId
    const maxChecks  = 40   // 40 × 3s = 2 minutes max
    let   checkCount = 0

    this.continuationCheckInterval = setInterval(async () => {
      checkCount++

      try {
        const response = await fetch(`/stories/${storyId}/status`, {
          headers: { "Accept": "application/json" }
        })
        if (!response.ok) return

        const data = await response.json()

        if (data.continuation_audio_url) {
          // Audio de la suite prêt — on enregistre son URL pour un Play instantané
          clearInterval(this.continuationCheckInterval)
          this.continuationCheckInterval = null
          if (this.pendingContinuation) {
            this.pendingContinuation.audioUrl = data.continuation_audio_url
          }
          // Si l'enfant n'écoute pas : on cache le chargement et on pulse le bouton.
          // S'il écoute, on laisse le badge ; le chaînage onended le cachera à la fin.
          if (!listening) {
            this.hidePreparing()
            this.markContinuationReady()
          }
        } else if (checkCount >= maxChecks) {
          // Timeout — on arrête ; le clic Play déclenchera la génération à la demande
          clearInterval(this.continuationCheckInterval)
          this.continuationCheckInterval = null
          this.hidePreparing()
        }
      } catch (e) {
        // Erreur réseau — on continue à poller sans crasher
      }
    }, 3000)
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
    // Arrête le pré-polling si l'utilisateur quitte la page avant que l'audio soit prêt
    if (this.preCheckInterval) {
      clearInterval(this.preCheckInterval)
      this.preCheckInterval = null
    }
    // Arrête le polling de l'audio de la suite si l'utilisateur quitte avant qu'il soit prêt
    if (this.continuationCheckInterval) {
      clearInterval(this.continuationCheckInterval)
      this.continuationCheckInterval = null
    }
    document.removeEventListener("story:continuation-ready", this.onContinuationReady)
  }

  // ============================================================
  // updateProgress() — met à jour la barre et le timer
  // ============================================================
  updateProgress() {
    if (!this.audio || !this.audio.duration) return

    const ratio = this.audio.currentTime / this.audio.duration

    // Largeur de la barre en pourcentage (panneau déplié)
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${ratio * 100}%`
    }

    // Anneau autour du bouton flottant : on réduit le dashoffset pour le remplir
    // (plein = 0). Math.max évite tout offset négatif si ratio dépasse 1.
    if (this.hasRingTarget) {
      this.ringTarget.style.strokeDashoffset = Math.max(0, this.RING_CIRC * (1 - ratio))
    }

    const current = this.formatTime(this.audio.currentTime)

    // Temps écoulé affiché dans le panneau
    if (this.hasCurrentTimeTarget) {
      this.currentTimeTarget.textContent = current
    }

    // Bulle "écoulé / total" (lecteur replié)
    if (this.hasBubbleTarget) {
      this.bubbleTarget.textContent = `${current} / ${this.formatTime(this.audio.duration)}`
    }
  }

  // ============================================================
  // resetProgress() — remet la barre, l'anneau et les timers à zéro
  // ============================================================
  resetProgress() {
    if (this.hasProgressBarTarget)  this.progressBarTarget.style.width = "0%"
    // Anneau remis à vide (dashoffset = circonférence complète)
    if (this.hasRingTarget)         this.ringTarget.style.strokeDashoffset = this.RING_CIRC
    if (this.hasCurrentTimeTarget)  this.currentTimeTarget.textContent  = "0:00"
    if (this.hasTotalTimeTarget)    this.totalTimeTarget.textContent    = "--:--"
    if (this.hasBubbleTarget)       this.bubbleTarget.textContent       = "0:00 / --:--"
  }

  // ============================================================
  // updateButtons(isPlaying) — synchronise l'état des boutons
  // ============================================================
  updateButtons(isPlaying) {
    this.playing = isPlaying

    // Bascule play ↔ pause dans le panneau déplié
    if (this.hasPlayBtnTarget)  this.playBtnTarget.classList.toggle("d-none", isPlaying)
    if (this.hasPauseBtnTarget) this.pauseBtnTarget.classList.toggle("d-none", !isPlaying)

    // Classe "is-playing" sur le conteneur : fait apparaître la bulle de temps
    // quand le lecteur est replié (voir _stories.scss).
    this.element.classList.toggle("is-playing", isPlaying)
  }

  // ============================================================
  // setLoading(isLoading) — état chargement sur les boutons Play
  // ============================================================
  // On désactive les boutons (FAB + panneau) et on s'appuie sur le CSS :disabled
  // pour l'indice visuel. On ne touche PAS au contenu HTML (il contient les SVG).
  setLoading(isLoading) {
    if (this.hasFabTarget)     this.fabTarget.disabled     = isLoading
    if (this.hasPlayBtnTarget) this.playBtnTarget.disabled = isLoading
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
