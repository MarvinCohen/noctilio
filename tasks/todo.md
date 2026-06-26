# Plan — Palier d'abonnement intermédiaire "Essentiel"

## Objectif
Passer d'une offre 2 niveaux (Gratuit / Premium 9,99€) à 3 niveaux :

| Niveau | Prix | Histoires | Illustrations IA | Audio | Mode interactif | Dashboard avancé |
|--------|------|-----------|------------------|-------|-----------------|------------------|
| Gratuit | 0€ | 3 / semaine | non* | non* | non* | non |
| **Essentiel** | **4,99€/mois** | **illimité** | **oui** | non | non | non |
| Premium | 9,99€/mois | illimité | oui | oui | oui | oui |

*Sauf la 1re histoire offerte (welcome_story) qui reste en expérience complète.

## Décision validée (2026-06-26)
- Essentiel = 4,99€/mois : histoires illimitées + illustrations IA, SANS audio ni interactif.
- Premium = 9,99€/mois : inchangé (tout).
- `premium?` garde son sens "haut de gamme" (audio + interactif + dashboard avancé).

## Pré-requis côté Stripe (action utilisateur, hors code)
- [ ] Créer un produit "Noctilio Essentiel" à 4,99€/mois dans le dashboard Stripe (mode test puis live).
- [ ] Récupérer son `price_...` et le mettre dans `STRIPE_ESSENTIEL_PRICE_ID` (Railway + .env dev).

## Cœur du chantier : décomposer le verrou unique
Aujourd'hui `User#full_experience_for?(story)` = `premium? || welcome_story?` contrôle À LA FOIS
illustration + audio + interactif. On le découpe en verrous par feature.

### Nouvelles méthodes dans `app/models/user.rb`
- [ ] `subscription_tier` → `:free` / `:essentiel` / `:premium` (admin = `:premium`).
      Lit `payment_processor.subscription&.processor_plan` et le compare aux deux price IDs.
      Plan payant inconnu → `:premium` (sécurité : ne jamais downgrader un payeur).
- [ ] `premium?` → `admin? || subscription_tier == :premium` (refonte interne, même sémantique externe).
- [ ] `essentiel?` → `subscription_tier == :essentiel`.
- [ ] `unlimited_stories?` → `subscription_tier != :free` (Essentiel ET Premium illimités).
- [ ] `illustrations_for?(story)` → `unlimited_stories? || welcome_story?(story)` (images : Essentiel+).
- [ ] `audio_for?(story)` → `premium? || welcome_story?(story)` (audio : Premium uniquement).
- [ ] `can_create_story?` → remplacer `return true if premium?` par `return true if unlimited_stories?`.
- [ ] Supprimer `full_experience_for?` et remplacer chaque appel par le verrou précis (voir ci-dessous).

### Remplacer les appels à `full_experience_for?`
- [ ] `app/jobs/generate_story_job.rb:81` (génération IMAGE) → `illustrations_for?(story)`.
- [ ] `app/jobs/generate_story_continuation_job.rb:46` (audio de la suite, déjà interactif=Premium) → `audio_for?(story)`.
- [ ] `app/controllers/stories_controller.rb:255` et `:302` (endpoint audio) → `audio_for?(@story)`.
- [ ] `app/views/stories/show.html.erb:143` (affichage illustration) → `illustrations_for?(@story)`.
- [ ] `app/views/stories/show.html.erb:245` (lecteur audio) → `audio_for?(@story)`.

### Inchangé (Premium uniquement, donc Essentiel exclu — c'est voulu)
- `app/models/story.rb:83` `interactive_requires_premium` → reste `premium?`.
- `app/views/stories/new.html.erb` toggle interactif (`premium? || first_story_pending?`) → reste.
- `app/views/parental/index.html.erb:768` dashboard avancé → reste `premium?`.

### À revoir (messaging selon le niveau)
- [ ] `app/views/dashboard/index.html.erb:91` upsell quota → conditionner sur `unlimited_stories?`
      (un Essentiel n'a plus de quota, on ne lui montre pas l'upsell "histoires illimitées").
- [ ] `app/views/shared/_navbar.html.erb:60` badge → afficher le bon libellé (Essentiel / Premium).
- [ ] `app/views/account/show.html.erb:51` statut d'abonnement → afficher le niveau réel.
- [ ] `app/views/stories/new.html.erb:61,411-418` bannières d'upsell → cohérentes avec Essentiel.

## Stripe checkout multi-plans
- [ ] `app/controllers/subscriptions_controller.rb#checkout` : accepter `params[:plan]`
      (`"essentiel"` / `"premium"`) et choisir le bon `price` (fallback premium).
- [ ] `config/routes.rb` : route checkout inchangée, on passe `plan` en param du formulaire.

## Page d'abonnement (3 niveaux)
- [ ] `app/views/subscriptions/index.html.erb` : 3 cartes de prix + 2 boutons "S'abonner"
      (Essentiel / Premium), tableau comparatif passé à 3 colonnes.
- [ ] i18n : nouvelles clés `subscription.*` (prix Essentiel, libellés, colonnes) dans
      les 6 langues : fr, en, de, es, it, pt.

## Tests (Minitest)
- [ ] `test/models/user_test.rb` : `subscription_tier` (free/essentiel/premium/admin),
      `unlimited_stories?`, `illustrations_for?`, `audio_for?`, `can_create_story?` par niveau.
      (On stube `payment_processor`/`subscription` ou on teste via admin + cas free.)
- [ ] Vérifier que la suite complète reste verte.

## Fichiers impactés (récap)
- app/models/user.rb, app/models/story.rb (lecture seule)
- app/jobs/generate_story_job.rb, app/jobs/generate_story_continuation_job.rb
- app/controllers/stories_controller.rb, app/controllers/subscriptions_controller.rb
- app/views/subscriptions/index.html.erb, stories/show.html.erb, stories/new.html.erb,
  dashboard/index.html.erb, shared/_navbar.html.erb, account/show.html.erb
- config/locales/{fr,en,de,es,it,pt}.yml
- CLAUDE.md (documenter STRIPE_ESSENTIEL_PRICE_ID + les 3 niveaux)
- test/models/user_test.rb

## Risque
Moyen. Le risque principal est de downgrader par erreur un Premium existant : le fallback
"plan inconnu → premium" et le test `subscription_tier` couvrent ce cas. Les comptes Premium
actuels gardent leur price ID → restent `:premium`.
