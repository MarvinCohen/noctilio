// Controller Stimulus — Révélation progressive des badges
// Affiche seulement les N premiers badges au chargement.
// "Voir plus" révèle tout + affiche "Voir moins".
// "Voir moins" replie + remonte au titre de la section.
// Pourquoi : 37 badges d'un coup = trop de scroll

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles : items de badge, bouton voir-plus, bouton voir-moins
  static targets = ["item", "btnMore", "btnLess"]

  // Valeur configurable depuis le HTML — nombre de badges visibles au départ
  static values = {
    limit: { type: Number, default: 8 }
  }

  // connect() masque les badges au-delà de la limite au chargement
  connect() {
    this.itemTargets.forEach((item, index) => {
      if (index >= this.limitValue) {
        item.classList.add("tr-badge-hidden")
      }
    })

    // Si tous les badges tiennent dans la limite, cache les deux boutons
    if (this.itemTargets.length <= this.limitValue) {
      this.btnMoreTarget.style.display = "none"
      this.btnLessTarget.style.display = "none"
    } else {
      // Met à jour le libellé avec le nombre de badges encore masqués
      this._updateMoreLabel()
      // "Voir moins" masqué au départ — visible seulement après dépliement
      this.btnLessTarget.style.display = "none"
    }
  }

  // Révèle tous les badges masqués
  // data-action="click->badge-reveal#reveal"
  reveal() {
    this.itemTargets.forEach(item => item.classList.remove("tr-badge-hidden"))

    // Échange les boutons : cache "Voir plus", affiche "Voir moins"
    this.btnMoreTarget.style.display = "none"
    this.btnLessTarget.style.display = "inline-flex"
  }

  // Replie les badges au-delà de la limite et remonte au titre de la section
  // data-action="click->badge-reveal#collapse"
  collapse() {
    this.itemTargets.forEach((item, index) => {
      if (index >= this.limitValue) {
        item.classList.add("tr-badge-hidden")
      }
    })

    // Échange les boutons : affiche "Voir plus", cache "Voir moins"
    this.btnLessTarget.style.display = "none"
    this.btnMoreTarget.style.display = "inline-flex"

    // Remonte au début de la section pour ne pas laisser l'utilisateur perdu
    this.element.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  // ── Privé ──────────────────────────────────────────────────────────────────

  _updateMoreLabel() {
    const hidden = this.itemTargets.length - this.limitValue
    this.btnMoreTarget.textContent = `Voir les ${hidden} autres trophées ✦`
  }
}
