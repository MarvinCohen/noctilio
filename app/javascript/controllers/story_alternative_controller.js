// ============================================================
// Stimulus Controller — story-alternative
// ============================================================
// Gère l'affichage de la "timeline alternative" d'un choix interactif.
//
// Fonctionnement :
//   1. L'utilisateur clique sur "Et si j'avais choisi [autre option]..."
//   2. Si le texte est déjà en cache (data-alternative-html) → on l'affiche directement
//   3. Sinon → requête POST vers /stories/:id/explore_alternative
//   4. Pendant le chargement → spinner
//   5. Une fois reçu → on insère le HTML dans la zone d'affichage
//
// Le texte alternatif est distingué visuellement du texte principal :
// fond légèrement différent + label "Et si..." en en-tête
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // url : l'endpoint POST /stories/:id/explore_alternative
  // choiceId : l'ID du StoryChoice à explorer
  // alternativeLabel : le texte du bouton (ex: "Option B : Retourner au village")
  static values = {
    url:              String,
    choiceId:         Number,
    alternativeLabel: String
  }

  // Cibles DOM manipulées par ce controller
  static targets = ["btn", "panel", "content", "spinner"]

  connect() {
    // Cache le panel au chargement — il s'ouvre à la demande
    this.panelTarget.style.display = "none"
    this._open = false
  }

  // ============================================================
  // toggle — ouvre ou ferme le panel alternatif
  // ============================================================
  async toggle() {
    if (this._open) {
      // Ferme le panel
      this._closePanel()
      return
    }

    // Si le contenu est déjà chargé (2ème clic) → affiche directement sans requête
    if (this._loaded) {
      this._openPanel()
      return
    }

    // Première ouverture → affiche le spinner, lance la requête
    this._showSpinner()
    this._openPanel()

    try {
      const response = await fetch(this.urlValue, {
        method:  "POST",
        headers: {
          "Content-Type":  "application/json",
          "X-CSRF-Token":  document.querySelector('meta[name="csrf-token"]').content,
          "Accept":        "application/json"
        },
        body: JSON.stringify({ choice_id: this.choiceIdValue })
      })

      const data = await response.json()

      if (data.success) {
        // Insère le HTML rendu par Redcarpet côté serveur
        this.contentTarget.innerHTML = data.html
        this._loaded = true
      } else {
        // Affiche le message d'erreur à la place du spinner
        this.contentTarget.innerHTML = `
          <p style="color: rgba(220,100,100,0.8); font-size: 0.85rem; margin: 0;">
            Impossible de générer cette alternative : ${data.error || "erreur inconnue"}
          </p>`
      }
    } catch (err) {
      // Erreur réseau
      this.contentTarget.innerHTML = `
        <p style="color: rgba(220,100,100,0.8); font-size: 0.85rem; margin: 0;">
          Erreur de connexion. Réessaie dans quelques instants.
        </p>`
    }

    // Masque le spinner une fois le contenu inséré
    this.spinnerTarget.style.display = "none"

    // Met à jour le label du bouton pour indiquer qu'on peut refermer
    this.btnTarget.textContent = "Masquer la timeline alternative"
  }

  // ============================================================
  // _openPanel / _closePanel — helpers de visibilité
  // ============================================================
  _openPanel() {
    this.panelTarget.style.display = "block"
    this._open = true
    this.btnTarget.setAttribute("aria-expanded", "true")
  }

  _closePanel() {
    this.panelTarget.style.display = "none"
    this._open = false
    this.btnTarget.setAttribute("aria-expanded", "false")
    // Remet le label original du bouton
    this.btnTarget.textContent = `Et si j'avais choisi "${this.alternativeLabelValue}" ?`
  }

  // ============================================================
  // _showSpinner — affiche le spinner de chargement
  // ============================================================
  _showSpinner() {
    // Vide le contenu précédent et affiche le spinner
    this.contentTarget.innerHTML = ""
    this.spinnerTarget.style.display = "flex"
  }
}
