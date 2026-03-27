# Noctilio — Contexte du projet

## C'est quoi Noctilio ?

Application Rails de génération d'histoires pour enfants par intelligence artificielle.
Les histoires sont personnalisées selon le profil de l'enfant (prénom, âge, personnalité).
L'IA génère le texte (GPT-4o) ET une illustration (DALL-E 3) pour chaque histoire.
Option : mode interactif où l'enfant fait des choix qui changent la suite de l'histoire.

## Développeur

Marvin Cohen — développeur junior Rails, premier projet solo post-formation Le Wagon.
**Règle absolue : commenter TOUT le code** (voir CLAUDE.md global).

## Stack technique

- Rails 8.1 + Le Wagon template + Devise (auth)
- PostgreSQL
- OpenAI : GPT-4o (texte) + DALL-E 3 (images)
- Solid Queue (jobs background — intégré Rails 8, pas Sidekiq)
- ActiveStorage (stockage images générées)
- Pay gem + Stripe (abonnements — pas encore configuré)
- Bootstrap 5 + Stimulus + Turbo (Hotwire)

## Architecture des modèles

```
User (Devise)
  ├── has_many :children
  ├── has_many :stories (through: :children)
  ├── has_many :user_badges
  └── pay_customer (Stripe — désactivé pour l'instant)

Child
  ├── belongs_to :user
  ├── has_many :stories
  └── champs : name, age, gender, hair_color, eye_color, skin_tone,
               personality_traits (jsonb), hobbies (jsonb), child_description

Story
  ├── belongs_to :child
  ├── has_many :story_choices
  ├── has_one_attached :cover_image (ActiveStorage)
  └── champs : title, content, world_theme, educational_value, reading_level,
               duration_minutes, custom_theme, status (enum), interactive,
               cover_image_url, image_prompt
  └── status enum : pending(0), generating(1), completed(2), failed(3)

StoryChoice (mode interactif)
  ├── belongs_to :story
  └── champs : step_number, question, option_a, option_b,
               chosen_option ('a'/'b'/nil), context_chosen

Badge + UserBadge
  └── système de trophées avec condition_key
```

## Services IA

- `app/services/story_generator_service.rb` — génère le texte via GPT-4o
- `app/services/image_generator_service.rb` — génère l'image via DALL-E 3

## Jobs (Solid Queue)

- `app/jobs/generate_story_job.rb` — orchestre génération texte + image
- `app/jobs/generate_story_continuation_job.rb` — génère la suite après un choix interactif

## Routes principales

```
GET  /                    → landing page (publique)
GET  /dashboard           → accueil après connexion
GET  /stories             → bibliothèque personnelle
GET  /stories/new         → formulaire création histoire
POST /stories             → lance GenerateStoryJob
GET  /stories/:id         → lecture + choix interactifs
GET  /stories/:id/status  → polling JSON du statut (Stimulus)
POST /stories/:id/choose  → enregistre un choix interactif
GET  /children            → liste des profils enfants
GET  /parental            → dashboard parental (stats)
GET  /trophees            → salle des trophées (badges + XP)
GET  /abonnement          → page abonnement (Stripe à configurer)
```

## Variables d'environnement (.env)

```
OPENAI_API_KEY=sk-...          # Obligatoire pour générer histoires et images
STRIPE_PREMIUM_PRICE_ID=...    # À configurer plus tard
```

## Flux de génération d'une histoire

1. Utilisateur remplit le formulaire (`/stories/new`)
2. `StoriesController#create` sauvegarde en base (status: pending)
3. `GenerateStoryJob.perform_later(story.id)` est lancé
4. Le job passe en status: generating
5. `StoryGeneratorService` appelle GPT-4o → retourne texte + titre
6. Si mode interactif : parse le bloc `[CHOIX]...[FIN CHOIX]` et crée un `StoryChoice`
7. `ImageGeneratorService` appelle DALL-E 3 → télécharge et attache à ActiveStorage
8. Story passe en status: completed
9. `Badge.check_and_award(user)` vérifie les badges
10. Le Stimulus `story_status_controller` poll `/stories/:id/status` toutes les 2s → redirige

## Mode interactif

Le GPT génère le texte avec un bloc spécial :
```
[CHOIX]
Question : Que doit faire Léo ?
Option A : Entrer dans la forêt sombre
Option B : Retourner au village
[FIN CHOIX]
```
Ce bloc est parsé par le job, crée un `StoryChoice`, et affiché en vue.
Après le choix, `GenerateStoryContinuationJob` génère la suite.

## Abonnement (à configurer plus tard)

- Gratuit : 3 histoires/mois
- Premium (9,99€/mois) : illimité + mode interactif
- `User#premium?` retourne `false` pour l'instant (Stripe pas encore configuré)
- Quand Stripe est prêt : remplacer `false` par `subscribed?` dans `user.rb`

## Univers disponibles

space, dinos, princesses, pirates, animals

## Valeurs éducatives

courage, sharing (partage), kindness (gentillesse), confidence (confiance)

## Badges (seeds)

first_story, five_stories, ten_stories, night_owl, kind_heart

## Commandes utiles

```bash
rails server           # Lancer le serveur
rails db:migrate       # Appliquer les migrations
rails db:seed          # Créer les badges
rails routes           # Voir toutes les routes
rails console          # Console Rails
```
