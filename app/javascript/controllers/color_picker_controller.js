// ============================================================
// ColorPickerController — Stimulus
// Gère les sélecteurs de couleur (cheveux, yeux, peau) du profil enfant.
//
// Pourquoi des DIV et pas des label ?
// .ch-form-section label { display: block } dans le CSS global cassait
// le layout flex des swatches. Les DIV ne sont pas ciblés par cette règle.
// Stimulus se charge de cocher le radio caché quand on clique sur un DIV.
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["indicator", "dot", "label", "radio", "swatches"]

  // connect() — appelé au montage du controller
  // Marque le swatch initialement sélectionné avec la classe CSS active
  connect() {
    this.radioTargets.forEach(radio => {
      if (radio.checked) {
        radio.closest(".cpk-swatch")?.classList.add("cpk-swatch--selected")
      }
    })
  }

  // pick() — appelé au clic sur un DIV.cpk-swatch
  // Coche le radio caché, met à jour l'indicateur et les classes visuelles
  pick({ currentTarget, params: { color, label } }) {
    // 1. Trouve et coche le radio à l'intérieur du div cliqué
    const radio = currentTarget.querySelector("input[type='radio']")
    if (radio) radio.checked = true

    // 2. Retire la sélection de tous les swatches du groupe
    this.swatchElements.forEach(s => s.classList.remove("cpk-swatch--selected"))

    // 3. Ajoute la sélection sur le swatch cliqué
    currentTarget.classList.add("cpk-swatch--selected")

    // 4. Met à jour le point coloré dans la pill indicateur
    if (this.hasDotTarget) {
      this.dotTarget.style.background = color
      this.dotTarget.style.display = "block"
    }

    // 5. Met à jour le texte du nom dans la pill indicateur
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = label
    }

    // 6. Animation pulse sur la pill
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.classList.remove("cpk-selected--pulse")
      // Reflow forcé pour relancer l'animation si on clique plusieurs fois
      void this.indicatorTarget.offsetWidth
      this.indicatorTarget.classList.add("cpk-selected--pulse")
    }
  }

  // Retourne tous les divs .cpk-swatch dans ce groupe
  get swatchElements() {
    return this.element.querySelectorAll(".cpk-swatch")
  }
}
