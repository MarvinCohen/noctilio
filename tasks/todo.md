# Plan — Corrections critiques 1 et 2 (protection des coûts)

## Objectif
Boucher deux trous identifiés par la revue de code :
1. Les actions `replay` et `continue` créent de nouvelles histoires sans
   revérifier le quota gratuit (3/semaine) → un compte gratuit épuisé peut
   relancer des générations.
2. rack-attack ne throttle que `POST /stories` ; les routes coûteuses
   `replay`, `continue`, `retry`, `choose` lancent chacune un job IA sans
   limite de débit dédiée.

## Fichiers impactés
- app/controllers/stories_controller.rb (before_action check_story_limit!)
- config/initializers/rack_attack.rb (nouveau throttle + commentaire corrigé)

## Étapes
- [x] 1. Ajouter `:replay` et `:continue` au `before_action :check_story_limit!`
- [x] 2. Ajouter un throttle rack-attack pour /stories/:id/(replay|continue|retry|choose)
- [x] 3. Corriger le commentaire obsolète (GPT-4o+DALL-E → Groq/gpt-image-1)
- [x] 4. Lancer `bin/rails test` → suite verte (247 runs, 0 failures)
