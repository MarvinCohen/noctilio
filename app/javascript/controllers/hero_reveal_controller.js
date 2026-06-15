// Controller Stimulus — Révélation progressive des héros (profils enfants)
// Affiche seulement les N premiers héros au chargement.
// "Voir plus" révèle tout + affiche "Voir moins".
// "Voir moins" replie + remonte en haut de la liste.
// Pourquoi : quand un compte a beaucoup d'enfants, la colonne "Mes Héros"
// rend la page parentale trop longue. On garde la liste compacte par défaut.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles : lignes de héros, bouton voir-plus, bouton voir-moins
  static targets = ["item", "btnMore", "btnLess"]

  // Valeur configurable depuis le HTML — nombre de héros visibles au départ
  static values = {
    limit: { type: Number, default: 5 }
  }

  // connect() masque les héros au-delà de la limite au chargement
  connect() {
    this.itemTargets.forEach((item, index) => {
      if (index >= this.limitValue) {
        item.classList.add("par-hero-row-hidden")
      }
    })

    // Si tous les héros tiennent dans la limite, cache les deux boutons
    if (this.itemTargets.length <= this.limitValue) {
      this.btnMoreTarget.style.display = "none"
      this.btnLessTarget.style.display = "none"
    } else {
      // Met à jour le libellé avec le nombre de héros encore masqués
      this._updateMoreLabel()
      // "Voir moins" masqué au départ — visible seulement après dépliement
      this.btnLessTarget.style.display = "none"
    }
  }

  // Révèle tous les héros masqués
  // data-action="click->hero-reveal#reveal"
  reveal() {
    this.itemTargets.forEach(item => item.classList.remove("par-hero-row-hidden"))

    // Échange les boutons : cache "Voir plus", affiche "Voir moins"
    // display:block pour rester pleine largeur (cf. .par-hero-toggle)
    this.btnMoreTarget.style.display = "none"
    this.btnLessTarget.style.display = "block"
  }

  // Replie les héros au-delà de la limite et remonte en haut de la liste
  // data-action="click->hero-reveal#collapse"
  collapse() {
    this.itemTargets.forEach((item, index) => {
      if (index >= this.limitValue) {
        item.classList.add("par-hero-row-hidden")
      }
    })

    // Échange les boutons : affiche "Voir plus", cache "Voir moins"
    // display:block pour rester pleine largeur (cf. .par-hero-toggle)
    this.btnLessTarget.style.display = "none"
    this.btnMoreTarget.style.display = "block"

    // Remonte au début de la liste pour ne pas laisser l'utilisateur perdu
    this.element.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  // ── Privé ──────────────────────────────────────────────────────────────────

  // Met à jour le libellé du bouton "Voir plus" selon le nombre de héros masqués
  // Gère le pluriel : 1 héros / N héros
  _updateMoreLabel() {
    const hidden = this.itemTargets.length - this.limitValue
    const label = hidden > 1 ? `Voir les ${hidden} autres héros` : "Voir 1 autre héros"
    this.btnMoreTarget.textContent = label
  }
}
