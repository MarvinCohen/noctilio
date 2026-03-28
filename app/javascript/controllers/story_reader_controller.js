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
      // Masque les contrôles si le navigateur ne supporte pas la synthèse vocale
      this.element.querySelector(".reader-controls")?.classList.add("d-none")
      return
    }

    // Stocke l'objet SpeechSynthesisUtterance courant
    this.utterance = null
    // Indicateur d'état : true si une lecture est en cours
    this.playing = false

    // Pré-charge les voix dès que possible
    // getVoices() est asynchrone au premier appel — le navigateur déclenche "voiceschanged"
    // quand la liste est prête. On écoute cet événement pour mettre les voix en cache.
    this.voices = []
    this.loadVoices()

    // Sur certains navigateurs (Chrome), les voix arrivent en différé via cet événement
    window.speechSynthesis.addEventListener("voiceschanged", () => this.loadVoices())
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

    // Annule toute lecture précédente pour éviter les lectures superposées
    window.speechSynthesis.cancel()

    // Récupère le texte brut depuis la cible "text" (le div de l'histoire)
    const text = this.textTarget.innerText || this.textTarget.textContent

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
    this.utterance.onerror = () => this.updateButtons(false)

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

  // disconnect() est appelé automatiquement par Stimulus quand on quitte la page
  // Garantit que la lecture s'arrête si l'utilisateur navigue vers une autre page
  disconnect() {
    if (this.supported) {
      window.speechSynthesis.cancel()
      window.speechSynthesis.removeEventListener("voiceschanged", () => this.loadVoices())
    }
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
