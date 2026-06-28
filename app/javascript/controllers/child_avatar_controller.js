// ============================================================
// Stimulus Controller : child-avatar
// ============================================================
// Prévisualisation LIVE de l'avatar de l'enfant dans le formulaire :
// quand on choisit une couleur de cheveux, d'yeux ou de peau, un petit
// visage SVG se met à jour instantanément avec la bonne couleur.
//
// Principe : chaque radio porte deux data-attributes :
//   data-avatar-part="hair" | "eyes" | "skin"  → quelle partie colorer
//   data-avatar-color="#xxxxxx"                 → la couleur à appliquer
// Au changement, update() lit ces attributs et peint la partie du SVG.
//
// Les cibles (targets) du SVG :
//   - skin : le visage + les oreilles
//   - hair : la chevelure
//   - eyes : les deux yeux (cible multiple → eyesTargets)
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["skin", "hair", "eyes"]

  // connect() — au chargement, on applique les couleurs déjà cochées
  // (utile en modification d'un profil enfant existant : l'avatar reflète l'état)
  connect() {
    // Pour chaque partie, on cherche le radio coché et on applique sa couleur
    this.element.querySelectorAll("input[type=radio]:checked").forEach((radio) => {
      this.paint(radio.dataset.avatarPart, radio.dataset.avatarColor)
    })
  }

  // update(event) — appelé par data-action="change->child-avatar#update"
  // sur chaque radio de couleur. Lit la partie + la couleur et repeint.
  update(event) {
    const radio = event.target
    this.paint(radio.dataset.avatarPart, radio.dataset.avatarColor)
  }

  // paint(part, color) — applique la couleur à la bonne partie du SVG
  paint(part, color) {
    if (!part || !color) return

    if (part === "skin" && this.hasSkinTarget) {
      // Le visage et les oreilles partagent la même teinte de peau
      this.skinTargets.forEach((el) => { el.style.fill = color })
    } else if (part === "hair" && this.hasHairTarget) {
      this.hairTarget.style.fill = color
    } else if (part === "eyes") {
      // Deux yeux → on colore chaque cible "eyes"
      this.eyesTargets.forEach((el) => { el.style.fill = color })
    }
  }
}
