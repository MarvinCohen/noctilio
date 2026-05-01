// ============================================================
// Stimulus Controller — story-creation
// ============================================================
// Gère le formulaire de création d'histoire en mode wizard :
//   1. Navigation entre les étapes (next / prev)
//   2. Indicateurs de progression (barre + cercles numérotés)
//   3. Validation par étape avant d'avancer
//   4. Retour visuel des cartes de sélection (radio/checkbox)
//   5. Feedback bouton pendant la génération
//   6. Insertions d'idées sans écraser le texte existant
//   7. Mise à jour du récapitulatif (étape 5)
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles Stimulus — éléments référencés dans la vue
  static targets = [
    "submitBtn",       // Bouton de soumission final
    "childError",      // Message d'erreur si aucun enfant sélectionné
    "step",            // Chaque étape (.wizard-step)
    "indicator",       // Chaque cercle indicateur (.wizard-indicator)
    "progressFill",    // Barre de progression dorée
    "stepTitle",       // Titre "Étape X / N" dans l'en-tête
    // Récap étape 6
    "summaryChildren", // Résumé : nom(s) des enfants
    "summaryTheme",    // Résumé : thème libre
    "summaryValue",    // Résumé : valeur éducative
    "summaryDuration", // Résumé : durée
    "summaryInteractive", // Résumé : mode interactif
    "summaryStyle"     // Résumé : style illustration
  ]

  // Nombre total d'étapes — mis à jour dans connect()
  totalSteps = 5

  // Étape courante (1-indexée)
  currentStep = 1

  // Libellés des valeurs éducatives pour le récap
  valueLabels = {
    courage:    "Courage",
    sharing:    "Partage",
    kindness:   "Gentillesse",
    confidence: "Confiance"
  }

  // Libellés des styles d'illustration pour le récap
  styleLabels = {
    ghibli:     "Studio Ghibli",
    comics:     "Comics",
    pixar:      "Pixar / Disney",
    watercolor: "Conte illustré"
  }

  // ============================================================
  // connect() — initialisation au chargement de la page
  // ============================================================
  connect() {
    // Détecte le nombre réel d'étapes dans le DOM
    this.totalSteps = this.stepTargets.length

    // Applique l'état visuel initial (cartes déjà cochées après erreur Rails)
    this.refreshAllSelections()

    // Affiche la première étape sans animation (chargement initial)
    this._renderStepNoAnim()
    this._updateIndicators()
    this._updateProgress()

    // Écoute le toggle interactif en temps réel pour mettre à jour le récap instantanément
    const toggle = this.element.querySelector('input[name="story[interactive]"][type="checkbox"]')
    if (toggle) {
      toggle.addEventListener('change', () => {
        if (this.hasSummaryInteractiveTarget) {
          // Met à jour "Activé" / "Désactivé" dès le clic sur le toggle
          this.summaryInteractiveTarget.textContent = toggle.checked ? "Activé" : "Désactivé"
        }
      })
    }
  }

  // ============================================================
  // nextStep — avance à l'étape suivante après validation
  // ============================================================
  // Déclenché par data-action="click->story-creation#nextStep"
  nextStep(event) {
    event.preventDefault()

    // Valide l'étape courante avant d'avancer
    if (!this.validateCurrentStep()) return

    if (this.currentStep < this.totalSteps) {
      this.currentStep++
      if (this.currentStep === this.totalSteps) this.updateSummary()
      this.renderStep("next")
    }
  }

  // ============================================================
  // prevStep — retourne à l'étape précédente
  // ============================================================
  // Déclenché par data-action="click->story-creation#prevStep"
  prevStep(event) {
    event.preventDefault()
    if (this.currentStep > 1) {
      this.currentStep--
      this.renderStep("prev")
    }
  }

  // ============================================================
  // onRadioChange — retour visuel sur les cartes radio
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
  // onCheckboxChange — validation en temps réel des enfants
  // ============================================================
  onCheckboxChange() {
    // Cache l'erreur dès qu'un enfant est sélectionné
    const checked = this.element.querySelectorAll('input[name="story[child_ids][]"]:checked')
    if (this.hasChildErrorTarget) {
      this.childErrorTarget.classList.toggle("d-none", checked.length > 0)
    }
  }

  // ============================================================
  // validateForm — validation finale avant soumission
  // ============================================================
  // Déclenché par data-action="submit->story-creation#validateForm"
  validateForm(event) {
    const checked = this.element.querySelectorAll('input[name="story[child_ids][]"]:checked')
    if (checked.length === 0) {
      event.preventDefault()
      if (this.hasChildErrorTarget) {
        this.childErrorTarget.classList.remove("d-none")
      }
      return
    }
    this.setSubmitting()
  }

  // ============================================================
  // insertIdea — insère une idée dans le textarea sans écraser
  // ============================================================
  insertIdea(event) {
    const textarea = document.getElementById("story_custom_theme")
    const idea     = event.currentTarget.dataset.idea
    if (!textarea || !idea) return

    const current = textarea.value.trim()
    textarea.value = current ? current + " " + idea : idea
    textarea.focus()
  }

  // ============================================================
  // renderStep — affiche l'étape courante avec animation de slide
  // direction : "next" (droite→gauche) ou "prev" (gauche→droite)
  // ============================================================
  renderStep(direction = "next") {
    const exitClass  = direction === "next" ? "wizard-step--exit-left"  : "wizard-step--exit-right"
    const enterClass = direction === "next" ? "wizard-step--enter-right" : "wizard-step--enter-left"

    // Étape actuellement visible (avant le changement)
    const outgoing = this.stepTargets.find(s => !s.classList.contains("d-none"))

      if (outgoing) {
      // Lance la sortie de l'étape courante
      outgoing.classList.add(exitClass)

      // Lance l'entrée de la nouvelle étape EN MÊME TEMPS (simultané)
      this._showIncoming(enterClass)

      // Nettoie l'étape sortante à la fin de son animation
      outgoing.addEventListener("animationend", () => {
        outgoing.classList.add("d-none")
        outgoing.classList.remove(exitClass)
        outgoing.style.position = "" // remet le flow normal
      }, { once: true })
    } else {
      // Premier affichage — pas d'animation de sortie
      this._showIncoming(enterClass)
    }
  }

  // Affiche l'étape cible avec animation d'entrée
  _showIncoming(enterClass) {
    const incoming = this.stepTargets[this.currentStep - 1]
    if (!incoming) return

    incoming.classList.remove("d-none")
    incoming.classList.add(enterClass)
    incoming.addEventListener("animationend", () => {
      incoming.classList.remove(enterClass)
    }, { once: true })

    // Met à jour indicateurs, barre de progression et titre
    this._updateIndicators()
    this._updateProgress()

    // Scroll vers le haut
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  // Mise à jour des cercles indicateurs
  _updateIndicators() {
    this.indicatorTargets.forEach((indicator, index) => {
      const stepNum = index + 1
      indicator.classList.remove("wizard-indicator--active", "wizard-indicator--done")

      if (stepNum < this.currentStep) {
        indicator.classList.add("wizard-indicator--done")
        indicator.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'
      } else if (stepNum === this.currentStep) {
        indicator.classList.add("wizard-indicator--active")
        indicator.textContent = stepNum
      } else {
        indicator.textContent = stepNum
      }
    })
  }

  // Mise à jour de la barre de progression et du label
  _updateProgress() {
    if (this.hasProgressFillTarget) {
      const pct = ((this.currentStep - 1) / (this.totalSteps - 1)) * 100
      this.progressFillTarget.style.width = pct + "%"
    }
    if (this.hasStepTitleTarget) {
      this.stepTitleTarget.textContent = `Étape ${this.currentStep} / ${this.totalSteps}`
    }
  }

  // Affichage initial sans animation (chargement de page)
  _renderStepNoAnim() {
    this.stepTargets.forEach((step, index) => {
      step.classList.toggle("d-none", index + 1 !== this.currentStep)
    })
  }

  // ============================================================
  // validateCurrentStep — vérifie les conditions de l'étape
  // ============================================================
  validateCurrentStep() {
    if (this.currentStep === 1) {
      // Étape 1 : au moins un enfant sélectionné
      const checked = this.element.querySelectorAll('input[name="story[child_ids][]"]:checked')
      if (checked.length === 0) {
        if (this.hasChildErrorTarget) {
          this.childErrorTarget.classList.remove("d-none")
        }
        return false
      }
      if (this.hasChildErrorTarget) {
        this.childErrorTarget.classList.add("d-none")
      }
    }
    return true
  }

  // ============================================================
  // updateSummary — remplit le récap de la dernière étape
  // ============================================================
  updateSummary() {
    // Noms des enfants sélectionnés
    if (this.hasSummaryChildrenTarget) {
      const checked = this.element.querySelectorAll('input[name="story[child_ids][]"]:checked')
      const names = Array.from(checked).map(input => {
        const label = input.closest("label")
        return label ? label.querySelector(".child-name")?.textContent?.trim() : ""
      }).filter(Boolean)
      this.summaryChildrenTarget.textContent = names.join(", ") || "—"
    }

    // Thème libre
    if (this.hasSummaryThemeTarget) {
      const textarea = this.element.querySelector('[name="story[custom_theme]"]')
      const val = textarea?.value?.trim()
      this.summaryThemeTarget.textContent = val
        ? (val.length > 60 ? val.substring(0, 60) + "…" : val)
        : "Non renseigné"
    }

    // Valeur éducative
    if (this.hasSummaryValueTarget) {
      const radio = this.element.querySelector('input[name="story[educational_value]"]:checked')
      this.summaryValueTarget.textContent = radio
        ? (this.valueLabels[radio.value] || radio.value)
        : "—"
    }

    // Durée
    if (this.hasSummaryDurationTarget) {
      const radio = this.element.querySelector('input[name="story[duration_minutes]"]:checked')
      this.summaryDurationTarget.textContent = radio ? radio.value + " min" : "—"
    }

    // Mode interactif
    if (this.hasSummaryInteractiveTarget) {
      const checkbox = this.element.querySelector('input[name="story[interactive]"][type="checkbox"]')
      this.summaryInteractiveTarget.textContent = checkbox?.checked ? "Activé" : "Désactivé"
    }

    // Style illustration — affiche le libellé français du style choisi, ou "Automatique" si aucun
    if (this.hasSummaryStyleTarget) {
      const radio = this.element.querySelector('input[name="story[image_style]"]:checked')
      this.summaryStyleTarget.textContent = radio
        ? (this.styleLabels[radio.value] || radio.value)
        : "Automatique"
    }
  }

  // ============================================================
  // Méthodes privées
  // ============================================================

  // Applique la classe "selected" sur les inputs déjà cochés
  refreshAllSelections() {
    this.element.querySelectorAll("input[type='radio']:checked, input[type='checkbox']:checked").forEach(input => {
      const label = input.closest("label")
      if (label) label.classList.add("selected")
    })
  }

  // Passe le bouton en état "génération en cours"
  setSubmitting() {
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
      this.submitBtnTarget.classList.add("btn-submitting")

      // Remplace le texte par un indicateur de chargement
      this.submitBtnTarget.innerHTML = `
        <span style="display:inline-flex;align-items:center;gap:8px;">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="animation:spin 1s linear infinite"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>
          Génération en cours…
        </span>
      `
    }
  }
}
