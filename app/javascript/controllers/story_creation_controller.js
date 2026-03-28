// ============================================================
// Stimulus Controller — story-creation
// ============================================================
// Rôle : gérer le retour visuel des cartes de sélection
// dans le formulaire de création d'histoire.
//
// Utilisé sur : app/views/stories/new.html.erb
// data-controller="story-creation" sur le div parent
//
// Ce controller écoute les changements des radio buttons
// et ajoute/retire une classe CSS "selected" sur les labels.
// Le CSS :has(input:checked) fait déjà le travail visuellement,
// mais ce controller sert aussi à fournir un retour plus explicite
// si besoin (accessibilité, animations supplémentaires).
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // Appelé automatiquement quand le controller est connecté au DOM
  connect() {
    // Met à jour le visuel des cartes déjà cochées au chargement de la page
    // (utile quand le formulaire est re-rendu après une erreur de validation)
    this.refreshAllSelections()
  }

  // Écoute tout changement sur un input radio dans le formulaire
  // Déclaré via data-action="change->story-creation#onRadioChange" dans la vue
  // ou en observant l'événement "change" sur le controller directement
  onRadioChange(event) {
    const radio = event.target

    // On ne traite que les radio buttons
    if (radio.type !== "radio") return

    // Trouve tous les labels du même groupe (même name) et retire "selected"
    const name = radio.name
    this.element.querySelectorAll(`input[type="radio"][name="${name}"]`).forEach(input => {
      // Remonte jusqu'au label parent et retire la classe "selected"
      const label = input.closest("label")
      if (label) label.classList.remove("selected")
    })

    // Ajoute "selected" sur le label de la radio cochée
    const activeLabel = radio.closest("label")
    if (activeLabel) activeLabel.classList.add("selected")
  }

  // ============================================================
  // Méthode privée — initialise l'état visuel au chargement
  // ============================================================

  // Parcourt tous les radios cochés et applique la classe "selected"
  refreshAllSelections() {
    this.element.querySelectorAll("input[type='radio']:checked").forEach(radio => {
      const label = radio.closest("label")
      if (label) label.classList.add("selected")
    })
  }
}
