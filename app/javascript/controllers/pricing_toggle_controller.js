// ============================================================
// Pricing Toggle Controller — Stimulus
// ============================================================
// Gère le bascule Mensuel / Annuel sur la page abonnement.
// Tout est rendu côté serveur (prix mensuels ET annuels stockés dans des
// data-attributes) : au clic sur un onglet, on remplace en JavaScript les
// textes affichés (montant + libellé de période) et on met à jour la valeur
// du champ caché "period" présent dans chaque formulaire de checkout, pour
// que Stripe reçoive la bonne période au moment du paiement.
//
// Cibles :
//   - tab    : les deux onglets (Mensuel / Annuel). Chacun porte data-period.
//   - price  : chaque montant de prix. Porte data-monthly et data-annual.
//   - period : chaque libellé de période ("par mois" / "par an · -25%").
//              Porte aussi data-monthly et data-annual.
// Les champs cachés name="period" (générés par button_to) sont retrouvés
// directement via querySelectorAll sur l'élément du controller.
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "price", "period"]

  // ── select(event) — appelé au clic sur un onglet Mensuel/Annuel ──
  // On lit la période choisie dans le data-period de l'onglet cliqué,
  // puis on applique le changement à toute la page.
  select(event) {
    const period = event.currentTarget.dataset.period
    this.#apply(period)
  }

  // ── #apply(period) — répercute la période "monthly" ou "annual" partout ──
  // Méthode privée (préfixe #) : centralise toute la mise à jour de l'affichage.
  #apply(period) {
    // 1. Montants : on remplace le texte par la valeur data-monthly / data-annual.
    //    dataset[period] lit data-monthly quand period === "monthly", etc.
    this.priceTargets.forEach((el) => {
      el.textContent = el.dataset[period]
    })

    // 2. Libellés de période ("par mois" / "par an · -25%") : même principe.
    this.periodTargets.forEach((el) => {
      el.textContent = el.dataset[period]
    })

    // 3. Champs cachés "period" des formulaires de checkout : on aligne leur
    //    valeur pour que Stripe reçoive la période effectivement choisie.
    this.element
      .querySelectorAll("input[name='period']")
      .forEach((input) => {
        input.value = period
      })

    // 4. Onglet actif : on ajoute la classe is-active à l'onglet correspondant
    //    et on la retire de l'autre (mise en valeur visuelle du choix).
    this.tabTargets.forEach((tab) => {
      tab.classList.toggle("is-active", tab.dataset.period === period)
    })
  }
}
