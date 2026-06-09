## Objectif

Corriger 3 bugs de la landing page sur Safari, qui ont une cause commune :
tout le JS est dans UN SEUL bloc `window.load` avec un try/catch global. Si une
instruction plante tôt (la lune, le curseur — Safari est plus strict sur
`ctx.ellipse()`), TOUT le reste est sauté → curseur figé (souris invisible via
`cursor: none`), étoiles jamais dessinées, bouton waitlist jamais branché.

Bugs :
1. La souris disparaît sur Safari (réapparaît sur l'input)
2. Le bouton "Accès anticipé" ne fait rien au clic
3. Les étoiles de fond sont invisibles

+ Demande : transformer le bouton en "Vous êtes bien inscrit" / "Vous êtes déjà inscrit"

## Fichiers impactés

- app/controllers/waitlist_controller.rb  → renvoyer un flag `already_subscribed`
- app/assets/stylesheets/landing.scss      → curseur natif visible si le JS échoue
- app/views/pages/home.html.erb            → isoler chaque module JS + texte du bouton

## Étapes

- [x] landing.scss : retirer `cursor: none` du body de base, le mettre sur `body.custom-cursor`
      (ajoutée par JS seulement quand le curseur custom est prêt → souris natif visible si plantage)
- [x] home.html.erb : envelopper CHAQUE module (lune, curseur, sillage, étoiles, formulaire)
      dans son propre try/catch → un module qui plante n'impacte plus les autres
- [x] home.html.erb : ajouter `document.body.classList.add('custom-cursor')` une fois le curseur init
- [x] waitlist_controller.rb : ajouter `already_subscribed: true` dans la réponse JSON
      quand l'échec vient de l'unicité de l'email (errors.details :taken)
- [x] home.html.erb : dans handleSubmit, transformer le bouton :
      - succès → "✦ Vous êtes bien inscrit" (désactivé)
      - déjà inscrit → "Vous êtes déjà inscrit" (désactivé)
      - autre erreur → message d'erreur classique
