// Controller Stimulus — lecture vocale de l'histoire
// Utilise l'API Web Speech (speechSynthesis) intégrée dans les navigateurs modernes
// Zéro dépendance, zéro coût — fonctionne sur Chrome, Edge, Safari, Firefox
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles déclarées :
  // - "text"     : le div contenant le texte de l'histoire à lire
  // - "playBtn"  : bouton "Écouter" / "Reprendre"
  // - "pauseBtn" : bouton "Pause"
  // - "stopBtn"  : bouton "Arrêter"
  static targets = ["text", "playBtn", "pauseBtn", "stopBtn"]

  // connect() est appelé automatiquement par Stimulus quand le controller est attaché au DOM
  connect() {
    // Vérifie que le navigateur supporte la synthèse vocale Web Speech API
    this.supported = "speechSynthesis" in window

    if (!this.supported) {
      // Cache les contrôles et affiche un message d'info pour les navigateurs sans support
      // (Firefox mobile, certains navigateurs Android ne supportent pas speechSynthesis)
      this.element.querySelector(".reader-controls")?.classList.add("d-none")
      const notice = this.element.querySelector(".reader-unsupported")
      if (notice) notice.classList.remove("d-none")
      return
    }

    // Stocke l'objet SpeechSynthesisUtterance courant
    this.utterance = null
    // Indicateur d'état : true si une lecture est en cours
    this.playing = false

    // Pré-charge les voix dès que possible
    this.voices = []
    this.loadVoices()
    window.speechSynthesis.addEventListener("voiceschanged", () => this.loadVoices())

    // Écoute l'événement déclenché par story_choice_controller quand la continuation
    // interactive est prête — reprend automatiquement la lecture sur le nouveau texte
    // IMPORTANT : (event) doit être passé pour que resumeAfterContinuation reçoive le texte
    this.onContinuationReady = (event) => this.resumeAfterContinuation(event)
    document.addEventListener("story:continuation-ready", this.onContinuationReady)
  }

  // Charge et met en cache la liste des voix disponibles
  // Appelée au connect() ET sur l'événement "voiceschanged"
  loadVoices() {
    this.voices = window.speechSynthesis.getVoices()
  }

  // Sélectionne la meilleure voix française disponible
  // Ordre de priorité : voix neurales Google > voix macOS Thomas/Amélie > n'importe quelle voix fr
  selectBestFrenchVoice() {
    const voices = this.voices.length ? this.voices : window.speechSynthesis.getVoices()

    // Priorité 1 : "Google français" — voix neuronale Chrome, nettement moins robotique
    const googleFr = voices.find(v => v.name === "Google français")
    if (googleFr) return googleFr

    // Priorité 2 : voix macOS Thomas (fr-FR) — naturelle sur Safari / Chrome Mac
    const thomas = voices.find(v => v.name === "Thomas")
    if (thomas) return thomas

    // Priorité 3 : voix macOS Amélie (fr-CA) — naturelle également
    const amelie = voices.find(v => v.name === "Amélie")
    if (amelie) return amelie

    // Priorité 4 : voix Microsoft françaises (Edge/Windows) — ex: "Microsoft Paul"
    const microsoftFr = voices.find(v => v.name.toLowerCase().includes("microsoft") && v.lang.startsWith("fr"))
    if (microsoftFr) return microsoftFr

    // Fallback : n'importe quelle voix fr-FR, puis fr-* en général
    return (
      voices.find(v => v.lang === "fr-FR") ||
      voices.find(v => v.lang.startsWith("fr")) ||
      null
    )
  }

  // Lance la lecture du texte de l'histoire
  // Appelée par data-action="click->story-reader#play"
  play() {
    if (!this.supported) return

    // Si la synthèse est en pause, on reprend simplement sans recréer l'utterance
    if (window.speechSynthesis.paused) {
      window.speechSynthesis.resume()
      this.updateButtons(true)
      return
    }

    // Chrome charge les voix de façon asynchrone — si elles ne sont pas encore
    // disponibles au moment du clic, on attend et on relance automatiquement
    const voices = window.speechSynthesis.getVoices()
    if (!voices.length) {
      console.log("story-reader: voix pas encore chargées, attente...")
      window.speechSynthesis.addEventListener("voiceschanged", () => this.play(), { once: true })
      return
    }

    // Recharge les voix au cas où elles ont changé depuis le connect()
    this.voices = voices

    // Annule toute lecture précédente pour éviter les lectures superposées
    window.speechSynthesis.cancel()

    // Récupère le texte brut depuis la cible "text" (le div de l'histoire)
    const text = this.textTarget.innerText || this.textTarget.textContent

    if (!text.trim()) return

    // Crée un objet SpeechSynthesisUtterance qui représente le texte à lire
    this.utterance = new SpeechSynthesisUtterance(text)

    // --- Configuration de la voix pour un rendu naturel ---
    this.utterance.lang   = "fr-FR" // Langue française pour une bonne prononciation
    this.utterance.rate   = 0.88    // Un peu plus lent — plus agréable pour les enfants
    this.utterance.pitch  = 1.05    // Légèrement plus aigu — plus chaleureux, moins robotique
    this.utterance.volume = 1.0     // Volume maximum

    // Applique la meilleure voix française disponible
    const bestVoice = this.selectBestFrenchVoice()
    if (bestVoice) this.utterance.voice = bestVoice

    // Callback déclenché quand la lecture se termine naturellement
    this.utterance.onend = () => this.updateButtons(false)

    // Callback déclenché en cas d'erreur de synthèse vocale
    this.utterance.onerror = (e) => {
      console.error("story-reader: erreur synthèse vocale", e)
      this.updateButtons(false)
    }

    // Lance effectivement la lecture
    window.speechSynthesis.speak(this.utterance)

    // Met les boutons en état "en cours de lecture"
    this.updateButtons(true)
  }

  // Met la lecture en pause sans la réinitialiser
  // Appelée par data-action="click->story-reader#pause"
  pause() {
    if (!this.supported) return
    window.speechSynthesis.pause()
    // Affiche à nouveau le bouton Play pour permettre de reprendre
    this.updateButtons(false)
  }

  // Arrête complètement la lecture et réinitialise l'état
  // Appelée par data-action="click->story-reader#stop"
  stop() {
    if (!this.supported) return
    // cancel() arrête la lecture ET vide la file d'attente
    window.speechSynthesis.cancel()
    this.utterance = null
    this.updateButtons(false)
  }

  // ============================================================
  // resumeAfterContinuation — lit UNIQUEMENT la continuation
  // ============================================================
  // Appelé via l'événement "story:continuation-ready".
  // event.detail.text contient le texte brut markdown de la continuation.
  // On le nettoie des symboles markdown avant de le lire.
  resumeAfterContinuation(event) {
    const html = event?.detail?.html
    if (!html) return

    // Extrait le texte brut depuis le HTML généré par Redcarpet côté serveur
    // On crée un élément temporaire pour utiliser innerText (nettoie les balises proprement)
    const tempDiv = document.createElement("div")
    tempDiv.innerHTML = html
    const cleanText = (tempDiv.innerText || tempDiv.textContent || "").trim()

    if (!cleanText) return

    setTimeout(() => {
      // Annule toute lecture en cours (l'histoire principale)
      window.speechSynthesis.cancel()

      // Crée un utterance avec UNIQUEMENT le texte de la continuation
      // → la lecture reprend juste après le choix, pas depuis le début
      const utterance = new SpeechSynthesisUtterance(cleanText)
      utterance.lang   = "fr-FR"
      utterance.rate   = 0.88
      utterance.pitch  = 1.05
      utterance.volume = 1.0

      const bestVoice = this.selectBestFrenchVoice()
      if (bestVoice) utterance.voice = bestVoice

      utterance.onend   = () => this.updateButtons(false)
      utterance.onerror = () => this.updateButtons(false)

      window.speechSynthesis.speak(utterance)
      this.utterance = utterance
      this.updateButtons(true)
    }, 400) // Petit délai pour laisser le DOM se stabiliser
  }

  // disconnect() est appelé automatiquement par Stimulus quand on quitte la page
  // Garantit que la lecture s'arrête si l'utilisateur navigue vers une autre page
  disconnect() {
    if (this.supported) {
      window.speechSynthesis.cancel()
      window.speechSynthesis.removeEventListener("voiceschanged", () => this.loadVoices())
    }
    // Retire le listener pour éviter les memory leaks
    document.removeEventListener("story:continuation-ready", this.onContinuationReady)
  }

  // Met à jour l'état des boutons selon si une lecture est en cours ou non
  // isPlaying : true → lecture en cours, false → lecture stoppée/en pause
  updateButtons(isPlaying) {
    this.playing = isPlaying

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
}
