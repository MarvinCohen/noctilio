// ============================================================
// Stimulus Controller — story-creation
// ============================================================
// Gère le formulaire de création d'histoire :
//   1. Retour visuel des cartes de sélection (radio/checkbox)
//   2. Validation : au moins un enfant coché avant soumission
//   3. Feedback bouton : spinner pendant la génération
//   4. Insertions d'idées sans écraser le texte existant
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles :
  // - "submitBtn"   : le bouton de soumission du formulaire
  // - "childError"  : message d'erreur si aucun enfant sélectionné
  static targets = ["submitBtn", "childError"]

  // connect() : initialise l'état visuel au chargement de la page
  connect() {
    // Applique la classe "selected" sur les cartes déjà cochées
    // (utile quand le formulaire est re-rendu après une erreur Rails)
    this.refreshAllSelections()

    // Met à jour l'état du bouton selon les enfants déjà cochés
    this.updateSubmitState()
  }

  // ============================================================
  // onRadioChange — retour visuel sur les cartes radio (valeur, durée)
  // ============================================================
  // Déclenché par data-action="change->story-creation#onRadioChange"
  onRadioChange(event) {
    const radio = event.target
    if (radio.type !== "radio") return

    // Retire "selected" de tous les labels du même groupe
    this.element.querySelectorAll(`input[type="radio"][name="${radio.name}"]`).forEach(input => {
      const label = input.closest("label")
      if (label) label.classList.remove("selected")
    })

    // Ajoute "selected" sur le label de la radio cochée
    const activeLabel = radio.closest("label")
    if (activeLabel) activeLabel.classList.add("selected")
  }

  // ============================================================
  // onCheckboxChange — valide en temps réel si un enfant est coché
  // ============================================================
  // Déclenché par data-action="change->story-creation#onCheckboxChange"
  onCheckboxChange(event) {
    // Cache le message d'erreur dès qu'un enfant est sélectionné
    this.updateSubmitState()
  }

  // ============================================================
  // validateForm — validation avant soumission
  // ============================================================
  // Déclenché par data-action="submit->story-creation#validateForm"
  // Bloque la soumission si aucun enfant n'est sélectionné
  validateForm(event) {
    const checked = this.element.querySelectorAll('input[name="story[child_ids][]"]:checked')

    if (checked.length === 0) {
      // Bloque l'envoi du formulaire
      event.preventDefault()

      // Affiche le message d'erreur sous la liste des enfants
      if (this.hasChildErrorTarget) {
        this.childErrorTarget.classList.remove("d-none")
      }
      return
    }

    // Formulaire valide — passe le bouton en état "chargement"
    // Empêche le double-clic et indique que la génération a commencé
    this.setSubmitting()
  }

  // ============================================================
  // insertIdea — insère une idée dans le textarea
  // ============================================================
  // Déclenché par data-action="click->story-creation#insertIdea"
  // N'écrase PAS le texte existant — ajoute à la fin si déjà rempli
  insertIdea(event) {
    const textarea = document.getElementById("story_custom_theme")
    const idea     = event.currentTarget.dataset.idea
    if (!textarea || !idea) return

    const current = textarea.value.trim()

    if (current) {
      // Texte existant : ajoute l'idée après, séparée par un espace
      // On ne remplace pas — le parent a peut-être déjà écrit quelque chose d'important
      textarea.value = current + " " + idea
    } else {
      // Textarea vide : insère directement
      textarea.value = idea
    }

    // Remet le focus sur le textarea pour que le parent continue d'écrire
    textarea.focus()
  }

  // ============================================================
  // Méthodes privées
  // ============================================================

  // Parcourt tous les inputs cochés et applique "selected" sur leur label
  refreshAllSelections() {
    this.element.querySelectorAll("input[type='radio']:checked, input[type='checkbox']:checked").forEach(input => {
      const label = input.closest("label")
      if (label) label.classList.add("selected")
    })
  }

  // Met à jour l'état du bouton et du message d'erreur selon les enfants cochés
  updateSubmitState() {
    const checked = this.element.querySelectorAll('input[name="story[child_ids][]"]:checked')
    const hasChild = checked.length > 0

    // Cache l'erreur si un enfant est maintenant coché
    if (this.hasChildErrorTarget) {
      this.childErrorTarget.classList.toggle("d-none", hasChild)
    }
  }

  // Passe le bouton en état "génération en cours"
  // Désactive le bouton pour éviter le double-clic
  setSubmitting() {
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.value    = "⏳ Génération en cours..."
      this.submitBtnTarget.disabled = true
      this.submitBtnTarget.classList.add("btn-submitting")
    }
  }
}
