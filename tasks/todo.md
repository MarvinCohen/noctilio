# Plan — Améliorations techniques 1 à 6

## Objectif
Renforcer la qualité technique de l'app : performances (mémoïsation), couverture
de tests sur les services IA, CI automatisée, monitoring des erreurs et détection
des requêtes N+1 en dev.

## Fichiers impactés
- app/models/user.rb (mémoïsation)
- test/services/story_generator_service_test.rb (nouveau)
- test/services/image_generator_service_test.rb (nouveau)
- Gemfile + config/initializers/sentry.rb (nouveau)
- config/environments/development.rb (config bullet)
- CLAUDE.md (correction : Groq/Llama 3.3, pas GPT-4o)

## Étapes
- [x] 1. Mémoïser `xp_points` dans user.rb (cache @xp_points)
- [x] 2. Mémoïser la requête `stories.minimum(:id)` de `welcome_story?` (first_story_id, cache via defined?)
- [x] 3. Tests des services IA (StoryGenerator : call succès/vide/erreur + helpers ; ImageGenerator : prompt/peau/action/softeners)
- [x] 4. CI GitHub Actions — déjà présent (ci.yml par défaut Rails 8.1 : rails test + brakeman + bundler-audit + rubocop)
- [x] 5. Sentry (sentry-ruby + sentry-rails + initializer) — no-op si SENTRY_DSN absent
- [x] 6. Gem bullet (groupe development + config after_initialize)
- [x] 7. CLAUDE.md corrigé (texte = Groq/Llama 3.3 ; variables d'env GROQ/OPENAI/FAL/SENTRY)
- [x] 8. Suite complète verte : 247 runs, 0 failures
