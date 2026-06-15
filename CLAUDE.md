# Noctilio — Contexte du projet

## C'est quoi Noctilio ?

Application Rails de génération d'histoires pour enfants par intelligence artificielle.
Les histoires sont personnalisées selon le profil de l'enfant (prénom, âge, personnalité).
L'IA génère le texte (GPT-4o) ET une illustration (gpt-image-1) pour chaque histoire.
Option : mode interactif où l'enfant fait des choix qui changent la suite de l'histoire.

## Développeur

Marvin Cohen — développeur junior Rails, premier projet solo post-formation Le Wagon.
**Règle absolue : commenter TOUT le code** (voir CLAUDE.md global).

## Stack technique

- Rails 8.1 + Le Wagon template + Devise (auth)
- PostgreSQL
- OpenAI : GPT-4o (texte) + gpt-image-1 (images, base64)
- Solid Queue (jobs background — intégré Rails 8, pas Sidekiq)
- ActiveStorage (stockage images générées)
- Pay gem + Stripe (abonnements — pas encore configuré)
- Bootstrap 5 + Stimulus + Turbo (Hotwire)

## Hébergement

- **Plateforme** : Railway (pas Heroku)
- **URL de production** : https://www.noctilio-app.fr (domaine canonical — sans www renvoie ECONNREFUSED)
- **Déploiement** : automatique depuis la branche `master` sur GitHub

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
               cover_image_url, image_prompt, image_style
  └── status enum : pending(0), generating(1), completed(2), failed(3)

StoryChoice (mode interactif)
  ├── belongs_to :story
  └── champs : step_number, question, option_a, option_b,
               chosen_option ('a'/'b'/nil), context_chosen

Badge + UserBadge
  └── système de trophées avec condition_key (37 badges définis dans les seeds)
```

## Services IA

- `app/services/story_generator_service.rb` — génère le texte via GPT-4o
- `app/services/image_generator_service.rb` — génère l'image via gpt-image-1 (base64)

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
GET  /histoire/:token     → partage public d'une histoire (lecture seule, token signé) — helper : shared_story_path
GET  /children            → liste des profils enfants
GET  /parental            → dashboard parental (stats)
GET  /trophees            → salle des trophées (badges + XP) — helper : trophy_room_path
GET  /abonnement          → page abonnement (Stripe à configurer)
GET  /cgu                 → Conditions Générales d'Utilisation (publique, indexée)
GET  /confidentialite     → Politique de confidentialité (publique, indexée)
GET  /mentions-legales    → Mentions légales (publique, indexée)
```

## Variables d'environnement

```
OPENAI_API_KEY=sk-...          # Obligatoire pour générer histoires et images

# --- Stripe (abonnement Premium) ---
# Le gem Pay lit ces variables d'ENV en priorité (sinon credentials).
# En dev : clés "test" (carte 4242 4242 4242 4242). En prod : clés "live" sur Railway.
STRIPE_PUBLIC_KEY=pk_...        # Clé publique (publishable) — utilisée côté client
STRIPE_PRIVATE_KEY=sk_...       # Clé secrète — appels serveur à l'API Stripe
STRIPE_SIGNING_SECRET=whsec_... # Secret de signature du webhook (vérifie l'authenticité des events)
                               # Webhook monté automatiquement par Pay sur /pay/webhooks/stripe
STRIPE_PREMIUM_PRICE_ID=price_... # ID du PRIX (price_, PAS prod_) de l'abonnement Premium
                               # Utilisé dans SubscriptionsController#checkout (line_items)

UMAMI_WEBSITE_ID=...           # ID du site Umami Cloud (analytics) — défini sur Railway uniquement.
                               # Absent en dev/test → le script de tracking est automatiquement désactivé.
                               # Voir AnalyticsHelper#umami_enabled? (off aussi pour les comptes admin).
```

## Flux de génération d'une histoire

1. Utilisateur remplit le formulaire (`/stories/new`)
2. `StoriesController#create` sauvegarde en base (status: pending)
3. `GenerateStoryJob.perform_later(story.id)` est lancé
4. Le job passe en status: generating
5. `StoryGeneratorService` appelle GPT-4o → retourne texte + titre
6. Si mode interactif : parse le bloc `[CHOIX]...[FIN CHOIX]` et crée un `StoryChoice`
7. `ImageGeneratorService` appelle gpt-image-1 → décode base64 → attache à ActiveStorage
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

## Univers disponibles

space, dinos, princesses, pirates, animals + thème libre (custom_theme)

## Styles visuels (image_style)

ghibli, comics, pixar, aquarelle, cinematique

## Valeurs éducatives

courage, sharing (partage), kindness (gentillesse), confidence (confiance)

## Badges (37 au total)

Catégories : progression (first_story, five_stories, ten_stories, twenty_stories),
univers (space_explorer, dino_rider, royal_heart, pirate_captain, animal_friend, world_traveler),
interactif (choice_maker, story_director), sagas (saga_starter, trilogy_master),
styles (ghibli_fan, comic_hero, pixar_dreamer, watercolor_soul, cinematic_pro, style_explorer),
valeurs (courage_heart, sharing_heart, confidence_heart),
thème libre (free_spirit, imaginative),
durée (quick_tales, epic_reader),
famille (collector),
horaires (night_owl, early_bird, weekend_tales),
bibliothèque (bookworm, story_keeper)

## Stimulus controllers

- `story_status_controller` — polling du statut de génération (toutes les 2s)
  - Targets : message (paragraphe de messages progressifs pendant la génération)
- `badge_reveal_controller` — révèle/replie les badges au-delà de la limite (8 par défaut)
  - Targets : item, btnMore, btnLess
  - Value : limit (default: 8)
- `share_controller` — copie le lien public d'une histoire dans le presse-papier
  - Targets : button
  - Value : url (lien signé à copier)

## SEO

- `public/robots.txt` — bloque les pages privées, autorise /, /cgu, /confidentialite, /mentions-legales, /blog
- `public/sitemap.xml` — 8 URLs publiques : landing, légales (×3), blog index + 3 articles
- `public/llms.txt` — description Noctilio pour les IA (ChatGPT, Perplexity, Gemini)
- `public/og-image.jpg` — image Open Graph dédiée 1536×1024 (générée via gpt-image-1)
- Layouts : robots dynamique via `content_for(:robots)` — par défaut noindex (app), index sur pages publiques
- Schema.org JSON-LD dans home.html.erb : SoftwareApplication + Organization + WebSite

### Blog SEO (statique, sans base de données)

- Controller : `app/controllers/blog_controller.rb` — ARTICLES constant, slug-based routing
- Routes : `GET /blog` → `blog#index`, `GET /blog/:slug` → `blog#show`
- Articles : `app/views/blog/_<slug>.html.erb` (partials)
- Articles actuels :
  - `histoires-du-soir-enfant` — "5 idées d'histoires du soir pour endormir son enfant"
  - `conte-personnalise-ia-enfant` — "Comment l'IA génère des contes personnalisés"
  - `histoires-enfant-4-ans` — "Histoires pour enfant de 4 ans : ce qui fonctionne vraiment"
- Lien "Blog" présent dans le footer partagé (`app/views/shared/_footer.html.erb`)

### ⚠️ Quand la landing page sera supprimée (/ devient dashboard)

Quand `/` sera protégé par Devise et redirigera vers `/users/sign_in`, il faudra :

1. **`robots.txt`** — remplacer `Allow: /` par `Disallow: /` pour l'app privée
2. **`sitemap.xml`** — retirer `/` ; garder uniquement `/blog/*` et les pages légales
3. **Schema.org** — déplacer le JSON-LD `SoftwareApplication` + `Organization` de `home.html.erb`
   vers une page publique permanente (layout landing, ou page `/a-propos` à créer)
4. **og:image** — vérifier qu'elle est servie sur toutes les pages publiques restantes
5. **Google Search Console** — soumettre le nouveau sitemap + inspecter les URLs
6. Le blog devient la principale vitrine SEO du site — prioriser les nouveaux articles

## Tests (Minitest)

Suite complète : 186 tests, 0 failures, 0 errors

Fichiers de test :
- `test/models/badge_test.rb` — 31 tests sur les 37 badges
- `test/models/story_test.rb` — validations + image_style
- `test/models/child_test.rb` — validations
- `test/models/user_test.rb` — associations
- `test/controllers/stories_controller_test.rb`
- `test/controllers/children_controller_test.rb`
- `test/controllers/dashboard_controller_test.rb`
- `test/controllers/parental_controller_test.rb`
- `test/controllers/trophy_room_controller_test.rb`
- `test/controllers/waitlist_controller_test.rb`

## Abonnement (Stripe configuré — mode TEST)

- **Gratuit** : 3 histoires/semaine (réinitialisé chaque lundi), TEXTE SEUL
  (ni illustration ni audio). Quota appliqué par `check_story_limit!`
  (before_action sur new/create dans StoriesController).
- **Premium** (9,99€/mois) : histoires illimitées + illustration IA + lecture audio
  + mode interactif.
- **Offre découverte** : la TOUTE PREMIÈRE histoire d'un compte gratuit est en accès
  complet (image + audio + interactif) pour donner envie de s'abonner.
  Voir `User#welcome_story?`, `User#full_experience_for?`, `User#first_story_pending?`.
- `User#premium?` : `true` si admin OU abonnement Pay/Stripe actif (`subscribed?`).
- Flux Stripe : `SubscriptionsController#checkout` → Stripe Checkout (hébergé) →
  `success`/`cancel`. Résiliation = période de grâce (`on_grace_period?`),
  réactivation possible via `#resume` tant que l'abonnement n'est pas terminé.
- ⚠️ Encore en mode TEST (carte 4242…). Pour facturer pour de vrai : passer en
  clés "live", configurer le webhook prod et les variables `STRIPE_*` sur Railway.

## Commandes utiles

```bash
rails server           # Lancer le serveur
rails db:migrate       # Appliquer les migrations
rails db:seed          # Créer les 37 badges
rails routes           # Voir toutes les routes
rails console          # Console Rails
rails test             # Lancer toute la suite de tests
```
