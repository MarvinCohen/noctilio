// ============================================================
// Stimulus Controller — story-quill
// ============================================================
// Effet "plume à encre" : chaque caractère apparaît un à un
// avec un effet encre (blur qui se dissipe + légère montée).
//
// Fonctionnement :
//   1. On parcourt tous les nœuds texte dans le HTML rendu
//   2. Chaque caractère est enveloppé dans un <span> avec
//      une animation CSS décalée (delay croissant)
//   3. L'animation simule l'encre qui sèche : opacité 0→1,
//      blur 4px→0, translateY 3px→0
//   4. Un curseur doré suit la fin du texte en cours d'écriture
//
// Pourquoi span par caractère plutôt que mot par mot ?
// → Un vrai effet plume se voit au niveau du tracé de chaque lettre.
//   Le délai entre caractères (18ms) donne l'illusion du trait.
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Délai entre chaque caractère en ms — ajustable via data-attribute
  static values = { speed: { type: Number, default: 18 } }

  // Injecte le CSS de l'animation une seule fois dans le <head>
  static _cssInjected = false

  connect() {
    this._injectCSS()
    // Petit délai pour laisser le DOM se stabiliser
    requestAnimationFrame(() => this.start())
  }

  // ============================================================
  // start — prépare le DOM et lance l'animation
  // ============================================================
  start() {
    // Collecte tous les nœuds texte non vides dans le contenu
    const textNodes = this._getTextNodes(this.element)
    if (!textNodes.length) return

    let charIndex = 0

    // Pour chaque nœud texte : remplace son contenu par des <span>
    // chacun portant un animation-delay croissant
    textNodes.forEach(node => {
      const text   = node.textContent
      const parent = node.parentNode

      // Crée un fragment pour éviter de reflow à chaque insertion
      const fragment = document.createDocumentFragment()

      for (let i = 0; i < text.length; i++) {
        const char = text[i]

        // Les espaces et sauts de ligne n'ont pas besoin d'animation
        if (/\s/.test(char)) {
          fragment.appendChild(document.createTextNode(char))
          continue
        }

        // Crée un span pour chaque caractère visible
        const span = document.createElement("span")
        span.className   = "sq-char"
        span.textContent = char
        // Décale l'animation selon l'index du caractère
        span.style.animationDelay = `${charIndex * this.speedValue}ms`
        fragment.appendChild(span)
        charIndex++
      }

      // Remplace le nœud texte original par les spans animés
      parent.replaceChild(fragment, node)
    })

    // Durée totale de l'animation
    const totalDuration = charIndex * this.speedValue

    // Ajoute le curseur clignotant doré à la fin du contenu
    const cursor = document.createElement("span")
    cursor.className = "sq-cursor"
    cursor.textContent = "✦"
    cursor.setAttribute("aria-hidden", "true")
    this.element.appendChild(cursor)

    // Retire le curseur une fois tout écrit
    setTimeout(() => {
      cursor.classList.add("sq-cursor--done")
      setTimeout(() => cursor.remove(), 800)
    }, totalDuration + 300)
  }

  // ============================================================
  // _injectCSS — injecte les keyframes et styles une seule fois
  // ============================================================
  _injectCSS() {
    if (story_quill_controller._cssInjected) return
    story_quill_controller._cssInjected = true

    const style = document.createElement("style")
    style.textContent = `
      /* Chaque caractère est invisible au départ */
      .sq-char {
        display: inline;
        opacity: 0;
        filter: blur(4px);
        transform: translateY(3px);
        animation: sq-ink 0.45s ease forwards;
      }

      /* Animation "encre qui sèche" :
         le caractère apparaît avec un léger flou qui se dissipe
         et remonte très légèrement (comme le tracé de la plume) */
      @keyframes sq-ink {
        0%   { opacity: 0;   filter: blur(4px);  transform: translateY(3px);  }
        40%  { opacity: 0.7; filter: blur(1.5px); transform: translateY(1px); }
        100% { opacity: 1;   filter: blur(0);    transform: translateY(0);    }
      }

      /* Curseur — petite étoile dorée Noctilio qui clignote */
      .sq-cursor {
        display: inline;
        color: #f0c97a;
        font-size: 0.7em;
        vertical-align: middle;
        margin-left: 3px;
        animation: sq-blink 0.6s step-end infinite;
      }
      @keyframes sq-blink {
        0%, 100% { opacity: 1; }
        50%       { opacity: 0; }
      }

      /* Disparition du curseur en fondu */
      .sq-cursor--done {
        animation: sq-cursor-out 0.8s ease forwards;
      }
      @keyframes sq-cursor-out {
        from { opacity: 1; }
        to   { opacity: 0; }
      }
    `
    document.head.appendChild(style)
  }

  // ============================================================
  // _getTextNodes — collecte récursivement les nœuds texte
  // ============================================================
  _getTextNodes(root) {
    const nodes = []
    const walker = document.createTreeWalker(
      root,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode(node) {
          if (!node.textContent.trim()) return NodeFilter.FILTER_REJECT
          const tag = node.parentElement?.tagName?.toLowerCase()
          if (tag === "script" || tag === "style") return NodeFilter.FILTER_REJECT
          return NodeFilter.FILTER_ACCEPT
        }
      }
    )
    let node
    while ((node = walker.nextNode())) nodes.push(node)
    return nodes
  }
}

// Référence statique pour éviter l'injection multiple du CSS
function story_quill_controller() {}
story_quill_controller._cssInjected = false
