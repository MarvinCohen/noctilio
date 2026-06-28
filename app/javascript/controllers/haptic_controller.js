// ============================================================
// Stimulus Controller : haptic
// ============================================================
// Déclenche une micro-vibration (retour haptique) au tap sur un élément,
// pour donner une sensation "app native" sur mobile (bottom-nav, choix…).
//
// navigator.vibrate n'est supporté que sur certains navigateurs mobiles
// (Chrome Android notamment ; iOS Safari l'ignore silencieusement). C'est
// donc une amélioration progressive : aucun effet ni erreur ailleurs.
//
// Utilisation dans la vue :
//   data-controller="haptic"            (sur le conteneur)
//   data-action="click->haptic#tap"     (sur le conteneur — les clics des
//                                         enfants remontent par bouillonnement)
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // tap() — vibre brièvement (10 ms) au clic/tap
  tap() {
    // Respecte le réglage "réduire les animations" : on s'abstient de vibrer
    // si l'utilisateur a demandé moins de stimuli (cohérent avec prefers-reduced-motion).
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    // vibrate n'existe pas partout — on vérifie avant d'appeler (sécurité).
    if (typeof navigator.vibrate === "function") {
      navigator.vibrate(10) // 10 ms : un simple "tic" discret, pas une vibration longue
    }
  }
}
