# NOCTILIO — Document de Synthèse Complète du Projet

## 1. Présentation du Projet

**Noctilio** est une application Rails 8 de génération d'histoires pour enfants via intelligence artificielle. L'app crée des récits personnalisés basés sur le profil de chaque enfant (prénom, âge, traits de personnalité, hobbies), puis génère automatiquement une illustration assortie.

### Concept clé
- **Personnalisation extrême** : chaque histoire est unique, adaptée à l'âge, aux intérêts et à la personnalité de l'enfant
- **Bimodalité storytelling** : texte + image (couverture illustrée)
- **Mode interactif optionnel** : l'enfant fait des choix qui influencent la suite de l'histoire
- **Gamification** : système de badges et XP pour encourager la lecture
- **Focus pédagogique** : chaque histoire transmet une valeur (courage, partage, gentillesse, confiance)

### Public cible
- Parents créant des histoires pour leurs enfants (3-15 ans)
- Pré-lancement avec waitlist (247+ inscrits)

### Développeur
Marvin Cohen — développeur junior Rails, premier projet solo post-formation Le Wagon.
**Règle absolue du projet** : commenter TOUT le code pour faciliter la maintenance.

---

## 2. Stack Technique Complète

### Versions clés
- **Rails** : 8.1.2
- **Ruby** : 3.3.5
- **PostgreSQL** : base de données relationnelle
- **Node.js** : avec Importmap + ESM (gestion des assets JavaScript)

### Gems importantes
```ruby
# Web framework
rails (~> 8.1.2)
puma
pg (~> 1.1)

# Hotwire (SPA-like experience)
turbo-rails       # Navigation rapide
stimulus-rails    # Stimulus controllers
importmap-rails   # ES6 modules sans bundler
jbuilder          # JSON API responses

# Authentification
devise            # Inscription, connexion, mot de passe

# UI/CSS
bootstrap (~> 5.3)
font-awesome-sass (~> 6.1)
simple_form
autoprefixer-rails
sassc-rails

# IA — Génération de contenu
ruby-openai (~> 7.0)    # Compatible Groq + DALL-E + OpenAI

# Stockage cloud des images
cloudinary (~> 1.29)
activestorage-cloudinary-service

# Abonnements Stripe
pay (~> 7.0)
stripe (~> 12.0)

# Job system intégré Rails 8
solid_queue
solid_cache
solid_cable

# Dev
dotenv-rails
```

---

## 3. Architecture des Modèles

### Diagramme des associations
```
User (Devise auth)
  ├── has_many :children
  ├── has_many :stories (through: :children)
  ├── has_many :user_badges
  └── pay_customer (Stripe integration)

Child
  ├── belongs_to :user
  ├── has_many :stories
  └── Champs : name, age, gender, hair_color, eye_color, skin_tone,
               personality_traits (jsonb), hobbies (jsonb), child_description

Story
  ├── belongs_to :child
  ├── has_many :story_choices
  ├── has_one_attached :cover_image (ActiveStorage)
  └── Champs : title, content, world_theme, custom_theme, educational_value,
               reading_level, duration_minutes, interactive, cover_image_url,
               image_prompt, saved, extra_child_ids (integer array)
  └── status enum : pending(0), generating(1), completed(2), failed(3)

StoryChoice (mode interactif)
  ├── belongs_to :story
  └── Champs : step_number, question, option_a, option_b,
               chosen_option ('a'/'b'/nil), context_chosen (suite générée)

Badge + UserBadge
  └── condition_key : first_story, five_stories, ten_stories, night_owl, kind_heart

WaitlistEntry
  └── email (unique, case-insensitive)
```

### Méthodes importantes

**User** :
- `premium?` — false pour l'instant (Stripe pas encore configuré)
- `can_create_story?` — gratuit: max 3/mois; premium: illimité
- `xp_points` — (stories.completed.count × 100) + (badges.count × 50)
- `full_name`

**Story** :
- `world_emoji` — retourne l'emoji de l'univers
- `all_children` — [child] + extra_children
- `next_choice` — prochain StoryChoice non résolu
- `has_pending_choice?` — true si interactive? && next_choice.present?
- `cover_image_source` — ActiveStorage ou cover_image_url (fallback)

**Badge** :
- `Badge.check_and_award(user)` — appelée après chaque histoire

**Scopes Story** :
- `completed`, `recent`, `completed_recent`, `saved_stories`

---

## 4. Controllers — Actions et Logique

### ApplicationController
```ruby
before_action :authenticate_user!
def after_sign_in_path_for(resource) = dashboard_path
def check_story_limit! # Vérifie quota mensuel
```

### PagesController
- `home` — landing page publique (skip authenticate_user!)
  - Layout "landing" spécial (sans navbar Rails)
  - Redirige vers dashboard si déjà connecté

### DashboardController
- `index` — `@recent_stories`, `@pending_stories`, `@children`, `@stories_this_month`

### ChildrenController
- CRUD complet (index, show, new, create, edit, update, destroy)
- Sécurité : `current_user.children.find(id)` (jamais `Child.find(id)`)

### StoriesController
- `new` — vérifie limite + redirige si aucun enfant
- `create` — crée story status:pending + lance GenerateStoryJob
- `show` — spinner si pas completed, affiche choix si interactive
- `choose` — enregistre choix + lance GenerateStoryContinuationJob
- `status` — endpoint polling JSON : `{ status, completed, continuation, redirect_url }`
- `save_story` — marque saved: true
- Sécurité : `current_user.stories.find(id)`

### AdminController
- `before_action :require_admin!` — vérifie email == "marvincohen95@gmail.com"
- `waitlist` (GET /admin/waitlist) — liste emails inscrits

### WaitlistController
- `create` — skip authenticate_user!, retourne JSON `{ success, count, error? }`

---

## 5. Services IA

### StoryGeneratorService

**API** : Groq (Llama 3.3 70B) via ruby-openai  
**URL** : `https://api.groq.com/openai/v1`  
**Modèle** : `llama-3.3-70b-versatile`  
**Température** : 0.85 (haute créativité)

**Méthodes** :
- `call` — génère l'histoire initiale
- `continue_with_choice(story_choice)` — génère la suite après un choix

**Tokens selon durée** : `{ 5 => 2000, 10 => 3500, 15 => 5500 }`

**Format mode interactif** (parsé par le job) :
```
[CHOIX]
Question : Que doit faire Léo ?
Option A : Entrer dans la forêt sombre
Option B : Retourner au village
[FIN CHOIX]
```

### ImageGeneratorService

**Stratégie fallback** (ordre de priorité) :
1. **fal.ai FLUX.1 Dev** — si FAL_API_KEY configurée (meilleure qualité, ~0,025$/img)
2. **DALL-E 3** — si OPENAI_API_KEY configurée (~0,04$/img)
3. **Pollinations.ai** — gratuit, dernier recours

**Méthodes** :
- `call` — orchestre la génération et le fallback
- `extract_key_moment` — extrait une scène clé du texte pour le prompt image

---

## 6. Background Jobs

### GenerateStoryJob
**Queue** : `:default` (Solid Queue)

**Flux** :
```
1. story.update(status: :generating)
2. StoryGeneratorService → texte depuis Groq
3. Parser titre (1ère ligne) + blocs [CHOIX]
4. ImageGeneratorService → image
5. story.update(status: :completed)
6. Badge.check_and_award(user)
```

### GenerateStoryContinuationJob
**Déclenché par** : StoriesController#choose

**Flux** :
```
1. StoryGeneratorService.continue_with_choice(choice)
2. choice.update(context_chosen: suite)
3. Parser nouveau [CHOIX] si présent
4. story.update(status: :completed)
5. Badge.check_and_award(user)
```

---

## 7. Routes Complètes

```ruby
GET  /                          → pages#home (landing, publique)
POST /waitlist                  → waitlist#create (inscription email)

GET  /dashboard                 → dashboard#index

resources :children             # CRUD complet

resources :stories, only: [:index, :show, :new, :create, :destroy] do
  member do
    post :choose                # Soumettre un choix interactif
    get  :status                # Polling JSON de génération
    post :save_story            # Marquer saved: true
  end
end

GET  /parental                  → parental#index (stats)
GET  /trophees                  → trophy_room#index (badges + XP)
GET  /abonnement                → subscriptions#index
POST /abonnement/checkout       → subscriptions#checkout (TODO Stripe)
POST /webhooks/stripe           → webhooks/stripe#create
GET  /admin/waitlist            → admin#waitlist (privé)
GET  /up                        → health check Heroku
```

---

## 8. Stimulus Controllers JavaScript

### story_status_controller.js
- Polling toutes les 2s sur `/stories/:id/status`
- Redirige quand `completed: true`, recharge si `status: "failed"`

### story_choice_controller.js
- Intercepte le clic sur un choix (preventDefault)
- POST JSON vers `/stories/:id/choose`
- Polling puis insertion de la continuation dans le DOM
- Déclenche l'événement `story:continuation-ready`
- Convertit markdown → HTML côté JS (`markdownToHtml()`)

### story_reader_controller.js
- Lecture vocale via Web Speech API (français)
- Voix prioritaire : Google fr → Thomas (macOS) → Amélie → Microsoft fr
- Paramètres : `rate: 0.88`, `pitch: 1.05`
- Écoute `story:continuation-ready` pour lire uniquement la nouvelle continuation

### story_creation_controller.js
- Gère la sélection visuelle des cartes radio dans le formulaire de création

### badge_check_controller.js
- Affiche un toast Bootstrap quand un badge est obtenu

---

## 9. Schéma de Base de Données (Principales Tables)

**users** : id, email, encrypted_password, first_name, last_name  
**children** : id, user_id, name, age, gender, hair_color, eye_color, skin_tone, personality_traits (jsonb), hobbies (jsonb), child_description  
**stories** : id, child_id, status (enum), title, content, world_theme, custom_theme, educational_value, reading_level, duration_minutes, interactive, cover_image_url, image_prompt, saved, extra_child_ids  
**story_choices** : id, story_id, step_number, question, option_a, option_b, chosen_option, context_chosen  
**badges** : id, name, condition_key, description, icon  
**user_badges** : id, user_id, badge_id, earned_at  
**waitlist_entries** : id, email (unique)  
**pay_*** : tables Stripe gérées par le gem Pay  
**solid_queue_*** : tables du job system  

---

## 10. État Actuel du Projet

### Ce qui fonctionne ✓
- Authentification Devise complète
- Profils enfants (CRUD)
- Génération d'histoires (Groq / Llama 3.3)
- Génération d'images (fal.ai → DALL-E → Pollinations)
- Mode interactif avec choix qui changent la suite
- Polling asynchrone (Stimulus, sans refresh)
- Lecture vocale (Web Speech API)
- Badges et système XP
- Dashboard parental (stats)
- Salle des trophées
- Waitlist pré-lancement (247+ inscrits)
- Page admin `/admin/waitlist`

### En cours ⚠️
- **Stripe** : gems installées, tables créées, routes présentes — mais `checkout` retourne "coming soon"
- `User#premium?` retourne `false` pour l'instant

### TODOs
- Implémenter SubscriptionsController#checkout
- Gérer webhooks Stripe
- Mettre à jour `User#premium?` pour appeler `subscribed?`
- Ajouter une suite de tests (aucun test écrit pour l'instant)
- Badge "bookworm" (condition définie mais non appliquée)

---

## 11. Déploiement — Heroku

### Procfile
```
web: bundle exec puma -C config/puma.rb
worker: bundle exec rails solid_queue:start
```
**Les deux processus sont obligatoires** — sans le worker, les jobs ne tournent pas.

### Variables d'environnement

**Obligatoires** :
- `GROQ_API_KEY` — clé API Groq (gratuite sur console.groq.com)
- `RAILS_MASTER_KEY`

**Optionnels** :
- `FAL_API_KEY` — fal.ai (meilleure qualité image)
- `OPENAI_API_KEY` — DALL-E (fallback image)

**Stripe (à configurer)** :
- `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_PREMIUM_PRICE_ID`

**Stockage images** :
- `CLOUDINARY_URL` — obligatoire en prod (Heroku filesystem éphémère)

### Commandes de déploiement
```bash
git push heroku master
heroku run rails db:migrate
heroku run rails db:seed
heroku ps:scale web=1 worker=1
heroku logs --tail
```

---

## 12. Conventions du Projet

- **Commentaires** : TOUT le code est commenté (règle absolue Marvin)
- **Fat Model, Skinny Controller** : la logique est dans les modèles et services
- **Services IA** : retournent `{ success: true/false, content/error: ... }`
- **Jobs** : idempotents, gèrent gracieusement les records supprimés
- **Sécurité** : toujours `current_user.children.find(id)` jamais `Child.find(id)`
- **Migrations** : forward-only (toujours ajouter une méthode `down`)
- **Git** : messages en français, branches `feature/nom-court`

---

## 13. Flux de Bout en Bout — Création d'Histoire

```
1. Formulaire (/stories/new)
   → Sélection enfant(s), univers, durée, valeur, niveau, mode interactif

2. StoriesController#create
   → Crée Story(status: pending)
   → GenerateStoryJob.perform_later(story.id)
   → Redirige vers /stories/:id (avec spinner)

3. Stimulus story_status_controller
   → Polling GET /stories/:id/status toutes les 2s
   → Attend { completed: true }

4. GenerateStoryJob
   → StoryGeneratorService (Groq) → texte
   → Parse titre + blocs [CHOIX] → crée StoryChoice
   → ImageGeneratorService → image
   → Story.update(status: :completed)
   → Badge.check_and_award(user)

5. Polling détecte completed → redirect /stories/:id
   → Affiche histoire + image + contrôles lecture vocale

6. Si interactive && has_pending_choice?
   → Affiche question + Option A/B

7. Choix → StoriesController#choose
   → GenerateStoryContinuationJob (même flux)
   → Continuation insérée dans DOM sans refresh
   → story_reader reprend la lecture vocale sur la continuation
```

---

*Document généré en avril 2026 — à mettre à jour après chaque fonctionnalité majeure.*
