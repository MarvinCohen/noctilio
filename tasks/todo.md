## Objectif
Transformer le front Noctilio en expérience type app mobile/store (esprit Duolingo
mais dans l'ADN nocturne et doux de Noctilio). Branche : feature/mobile-app-experience.
EXCLU : tout ce qui concerne le Play Store / TWA.

## Phases

### Phase 1 — Bottom tab bar mobile
- [x] Partial shared/_bottom_nav.html.erb (5 onglets : Accueil, Histoires, Créer central, Trophées, Profil)
- [x] components/_bottom_nav.scss (visible ≤768px, onglet actif halo doré, bouton central surélevé)
- [x] Import dans components/_index.scss
- [x] Branchement dans layouts/application.html.erb (connectés uniquement)
- [x] padding-bottom sur .app-main pour ne pas masquer le contenu

### Phase 2 — Accueil rituel du soir
- [x] Helper constellation du soir (modèle, non punitif) — User#recent_story_nights
- [x] Carte progression (orbe niveau + barre XP + trophées) — User#xp_in_current_level / level_progress / xp_to_next_level
- [x] Carte suggestion histoire du soir (1 tap)
- [x] Refonte dashboard/index.html.erb mobile-first (section db-ritual + SCSS)

### Phase 3 — Sensation app
- [x] Transitions de page Turbo (meta view-transition + components/_transitions.scss)
- [x] Animations au tap (scale boutons) — :active scale sur CTA + .tap-scale
- [x] Splash screen PWA (mode standalone uniquement, components/_splash.scss + JS layout)
- [x] Skeletons de chargement génération (story-skeleton dans show.html.erb + shimmer)

### Phase 4 — Onboarding première fois
- [x] Détection nouvel utilisateur sans enfant (dashboard branche sur @children.empty?)
- [x] Parcours plein écran (dashboard/_onboarding : 3 étapes héros -> univers -> 1re histoire offerte, CTA vers new_child_path puis wizard existant)

### Phase 5 — PWA niveau store (sans Play Store)
- [x] start_url -> dashboard (déjà /home = dashboard_path, confirmé dans le manifest)
- [x] Icônes dédiées par taille (public/icon-192.png, icon-512.png, apple-touch-icon.png 180) + manifest mis à jour
- [x] Splash screen iOS : splash in-app (.pwa-splash, Phase 3) actif en standalone iOS + background_color #0b0e1a + meta apple-mobile-web-app-status-bar-style/title + apple-touch-icon dédié. NB : pas d'images apple-touch-startup-image par appareil (trop fragile à maintenir, une image par taille d'écran iOS) -> le splash in-app couvre le besoin de façon cross-plateforme.
- [x] Lecture hors-ligne des histoires déjà ouvertes : service worker Network First (déjà en place) + correction de la liste de pré-cache (/ et /home au lieu de routes 404), bump CACHE_NAME v2, repli navigation sur la coquille /home hors-ligne, et on ne cache plus les réponses non-200/redirections

## Réorganisation navigation compte / espace parent

### Objectif
Simplifier l'accès au compte et au suivi parental. L'onglet "Profil" de la bottom
nav devient "Espace parent". L'avatar du top nav mène directement à "Mon compte"
(plus de menu dropdown). La déconnexion est déplacée dans la page Mon compte.

### Fichiers impactés
- app/views/shared/_bottom_nav.html.erb (onglet Profil -> Espace parent)
- app/views/shared/_sidebar.html.erb (avatar = lien direct vers Mon compte, suppression du dropdown)
- app/views/account/show.html.erb (ajout du bouton Déconnexion au-dessus de la zone Supprimer)
- app/assets/stylesheets/components/_sidebar.scss (avatar en lien, nettoyage styles dropdown devenus inutiles)

### Étapes
- [x] Bottom nav : remplacer l'onglet Profil (account_path) par Espace parent (parental_path), icône utilisateurs, label "Parents", actif si controller_name == 'parental'
- [x] Top nav : transformer l'avatar dropdown en lien direct vers account_path (retirer data-bs-toggle, le <ul> dropdown, les classes dropdown), garder la pastille niveau
- [x] Mon compte : ajouter un bouton Déconnexion (DELETE destroy_user_session_path) juste au-dessus de la zone "Supprimer mon compte"
- [x] SCSS : adapter .sidebar-user / .sidebar-user-avatar pour un simple lien, retirer les styles dropdown devenus morts
- [x] Tests : suite OK (220 runs, 0 failures) + assets précompilés

## Internationalisation (i18n) — app multilingue

### Objectif
Rendre Noctilio disponible en FR (existant) + EN + ES + DE + IT + PT, pour toucher
un maximum de personnes. Deux niveaux : (1) l'INTERFACE (boutons, menus, formulaires)
et (2) les HISTOIRES GÉNÉRÉES par l'IA. Détection auto de la langue au 1er accès +
sélecteur manuel. Langue par défaut : FR.

### Décisions
- Langues : fr (défaut), en, es, de, it, pt
- Portée : interface ET histoires générées
- Détection : auto (navigateur Accept-Language) au 1er accès, puis sélecteur manuel
  (mémorisé en session + sur le compte pour les connectés)
- ARCHITECTURE HYBRIDE (validée) :
  * App privée (dashboard, stories, compte…) -> langue via cookie/session + compte.
    Pas de préfixe d'URL : zéro coût SEO car l'app est déjà noindex/derrière login.
  * Pages publiques (landing, blog, légales) -> URLs préfixées /en/ /es/… + hreflang.
    C'est la seule zone indexée par Google, donc la seule où le SEO multilingue compte.
- Stratégie de livraison : construire d'abord le PIPELINE complet sur FR + EN, puis
  les 4 autres langues = juste remplir les fichiers de traduction (coût marginal faible)

### Phase 0 — Infrastructure i18n (le moteur) ✅
- [x] config/application.rb : available_locales [:fr,:en,:es,:de,:it,:pt], default :fr,
      fallbacks vers :fr (toute clé manquante retombe sur FR)
- [x] Migration : users.locale (string, default "fr") — mémorise la langue d'un connecté
- [x] ApplicationController : around_action switch_locale
      (ordre : params[:locale] > session > current_user.locale > navigateur > défaut)
      + persiste le choix en session ; helper locale_from_browser (Accept-Language)
- [x] App privée = cookie/session uniquement (PAS de préfixe URL). Décision verrouillée :
      hybride (URLs préfixées réservées aux pages publiques, traitées en Phase 4)
- [x] Route POST /langue + LocaleController#update (persiste session + compte)
- [x] Partial shared/_locale_switcher.html.erb (noms de langue) + SCSS _locale_switcher
- [x] Sélecteur branché dans la page Mon compte (carte "Langue")
- [x] Tests : suite verte (220 runs, 0 failures) + assets précompilés

### Phase 1 — Traductions interface FR + EN (pilote du pattern) ✅
- [x] Créer config/locales/fr.yml comme SOURCE DE VÉRITÉ : extraire les chaînes FR
      écrites en dur dans les vues (clés organisées par vue/contrôleur)
- [x] Créer config/locales/en.yml (miroir traduit)
- [x] Remplacer les chaînes en dur par <%= t(".cle") %> vue par vue
      (navigation/sidebar/bottom_nav -> dashboard -> stories -> account
       -> parental -> trophées -> abonnement -> blog/légales -> stories/show -> feedbacks/new)
- [x] Stimulus : chaînes injectées en JS passées par data-values (story_status,
      story_choice, story_alternative, story_image, share)
- [x] Devise + simple_form : compléter devise.en.yml / en.yml existants pour EN
- [x] Vérifier qu'aucune chaîne FR ne reste codée en dur (audit grep)

### Phase 2 — Histoires générées multilingues (le cœur IA)

PROBLÈME CENTRAL : les jobs Solid Queue tournent en arrière-plan où I18n.locale
revient à :fr. On ne peut PAS lire la locale courante dans le job -> la langue doit
être FIGÉE sur la Story à la création (colonne stories.locale), puis lue par le service.

Découpage en 3 lots indépendants. Recommandé : LOT 1 d'abord (fondation).

#### LOT 1 — Persistance de la langue (fondation) ✅
- [x] Migration : ajouter stories.locale (string, default "fr", null: false)
- [x] rails db:migrate
- [x] StoriesController#create : @story.locale = I18n.locale.to_s avant save
- [x] Test modèle : une Story a locale == "fr" par défaut
- [x] Test controller : create en ?locale=en enregistre locale == "en"
- [x] rails test (vert : 222 runs, 0 failures)

#### LOT 2 — Service IA multilingue (le cœur) ✅
- [x] Méthode privée language_name : mappe @story.locale -> nom de langue (en FR :
      "français", "anglais", "espagnol", "allemand", "italien", "portugais")
- [x] system_prompt : consigne de langue dynamique en tête (priorité absolue) basée
      sur language_name -> "écris TOUT le texte EN <LANGUE>" (approche minimale)
- [~] world_theme_prompt_label / educational_value_label : laissés en français
      (consignes lues par l'IA multilingue, pas du texte affiché) -> à traduire
      seulement si la qualité baisse (décision minimale validée)
- [x] Parsing [CHOIX] : note ajoutée dans interactive_user_prompt ET
      build_continuation_messages -> garder [CHOIX]/[FIN CHOIX]/Question/Option A/B
      littéraux (repères techniques du parseur du job), seul le contenu est traduit
- [x] GenerateStoryContinuationJob / GenerateStoryJob : rien à passer (service lit story.locale)
- [x] rails test (vert : 222 runs, 0 failures) + vérif runner (prompt "EN ANGLAIS" pour locale en)

#### LOT 3 — Libellés métier côté modèle/vue
- [x] Story#world_label -> I18n.t("worlds.<theme>") (+ namespace worlds dans fr/en)
- [x] Vérifier vues appelant world_label (toutes en contexte requête -> rien à changer)
- [x] Commentaire obsolète mis à jour dans children/show.html.erb
- [x] Tests modèle world_label (FR + EN + custom) -> rails test vert (224 runs, 0 failures)
#### LOT 3b — Refacto profils enfants (valeurs stables + i18n)
Aujourd'hui hair_color/eye_color/skin_tone/personality_traits stockent la chaîne
FR affichée. gender et hobbies utilisent déjà des valeurs stables [label, value].
NB : tous les enfants en base sont des données de TEST (créées par le dev) -> migration
de données sans risque.

Clés stables retenues :
- hair  : black, dark_brown, brown, dark_blonde, blonde, light_blonde, red, white
- eyes  : dark_brown, brown, hazel, dark_green, green, light_green, dark_blue, blue, light_blue, grey
- skin   : ebony, dark_brown, brown, caramel, golden, olive, beige, light, very_light
- traits : brave, curious, shy, funny, generous, creative, adventurous, gentle

- [x] i18n : namespace children.appearance.{hair,eyes,skin,traits}.* dans fr.yml + en.yml
- [x] _form.html.erb : remplacer les value="<FR>" par les clés stables, libellés via t()
      (cheveux, yeux, peau = radios ; traits = checkboxes). Points colorés inchangés.
- [x] children/index.html.erb : afficher le trait traduit (t("children.appearance.traits.#{trait}"))
- [x] children_helper.rb : hair_map / skin_map ré-indexés par clés stables (hex DiceBear)
- [x] child.rb avatar_description : traduit clé -> libellé FR via I18n.t(..., locale: :fr)
      (méthodes hair_color_fr / eye_color_fr / skin_tone_fr / trait_fr)
- [x] child.rb hair_color_en / eye_color_en / skin_tone_en : regex floues remplacées
      par un mapping EXACT clé -> anglais (nuances conservées : white -> platinum
      white-blonde, brown -> warm brown, ebony -> dark ebony, etc.)
- [x] Migration de données réversible (20260618110000) : ancien FR -> clé stable
      (+ down : clé -> FR) pour hair_color, eye_color, skin_tone, personality_traits.
      Traits obsolètes (déterminé, empathique…) supprimés (anciennes données de test).
- [x] rails db:migrate (données converties + vérifiées en console)
- [x] test/models/child_test.rb : avatar_description (FR) + image_description (EN) OK avec clés
      + tests des nuances white -> platinum white-blonde et brown -> warm brown
- [x] rails test (vert : 224 runs, 0 failures)

QUESTION OUVERTE : portée de la traduction des prompts -> commencer minimal (juste la
consigne de langue, l'IA gère le reste), puis traduire tout le system_prompt si besoin.

NB : prompts image déjà en anglais -> illustration inchangée.

### Phase 3 — Les 4 langues restantes (ES, DE, IT, PT)
- [x] config/locales/es.yml, de.yml, it.yml, pt.yml (interface, miroir complet de en.yml)
- [x] devise + simple_form pour chaque langue (devise.es/de/it/pt.yml + simple_form.es/de/it/pt.yml)
- [x] Vérifier les consignes de langue côté histoire pour les 4
      (story_generator_service language_name couvre déjà fr/en/es/de/it/pt)
- [x] rails test (vert : 226 runs, 0 failures)

### Phase 4 — SEO multilingue des PAGES PUBLIQUES (lot séparé)
Décision (2026-06-18) : INFRA D'ABORD, contenu traduit dans un 2e temps. 5 langues (en/es/de/it/pt).
FR = sans préfixe d'URL ; les 5 autres langues préfixées (/en/, /es/, /de/, /it/, /pt/).

Phase 4a — Infrastructure SEO (ce lot) :
- [x] Routes : scope "(:locale)" (locale: /en|es|de|it|pt/) autour des routes publiques
      (root, a-propos, cgu, confidentialite, mentions-legales, blog, blog/:slug)
- [x] ApplicationController#default_url_options : conserve le préfixe de langue dans les liens
- [x] Helper SEO (app/helpers/seo_helper.rb) : localized_url / canonical_url / og_locale
- [x] Partial shared/_hreflang.html.erb mutualisé (layout landing + layout application,
      ce dernier uniquement pour les pages indexées via content_for(:robots) = index)
- [x] html lang + og:locale dynamiques dans les deux layouts
- [x] sitemap.xml DYNAMIQUE (SitemapsController + show.xml.erb) : 14 pages x 7 hreflang,
      remplace public/sitemap.xml (supprimé). Réutilise BlogController::ARTICLES.
- [x] robots.txt vérifié : Allow:/ couvre les préfixes de langue, Disallow privés intacts
- [x] rails test (vert : 226 runs, 0 failures) + vérif intégration (sitemap 200,
      /en/cgu lang=en + canonical/hreflang OK, / et /en OK)

      RAPPEL : ne PAS déployer avant la Phase 4b si on ne veut pas que Google voie les
      pages des 5 langues encore en fallback FR (contenu non traduit). Le sitemap les
      annonce déjà. Déployer 4a+4b ensemble, ou retirer temporairement les langues du sitemap.

Phase 4b — Contenu éditorial (après validation de l'infra) :
Décision : pages légales (cgu / confidentialité / mentions-légales) restent en FR
(validité juridique) -> hreflang de ces pages pointe uniquement vers FR.

Slice 1 — Chrome + métadonnées blog ✅
- [x] config/locales/blog.<locale>.yml (fr/en/es/de/it/pt) : chrome (index, show, breadcrumb)
- [x] BlogHelper#blog_article_title / _description (traduit ou fallback FR du contrôleur)
- [x] blog/index + blog/show passés en t() + URLs localisées + dates I18n.l + inLanguage

Slice 2 — Métadonnées d'articles ✅
- [x] Bloc articles.<slug>.{title,description} dans les 5 fichiers blog.<locale>.yml
      (FR = fallback via default: depuis le contrôleur, non dupliqué)

Slice 3 — Corps des 8 articles ✅
- [x] 40 templates _<slug>.<locale>.html.erb (8 articles x 5 langues), prose traduite,
      structure ERB/HTML préservée, liens "à lire aussi" alignés sur les titres YAML
- [x] Vérif : 40 articles rendus en 200, aucun fallback FR ; suite verte (226 runs)

Slice 4 — Landing + à-propos ✅ :
- [x] Landing home.html.erb : chaînes FR -> clés i18n (home.<locale>.yml, 6 langues),
      objet JS I18N pour les messages du formulaire, Schema.org localisé (inLanguage dynamique)
- [x] à-propos a_propos.html.erb : clés i18n (about.<locale>.yml, 6 langues) + Schema.org Person localisé
- [x] Vérif : / + /a-propos rendus en 200 dans les 6 langues, aucune clé manquante ; suite verte (226 runs)
- [x] FAQs de 2 articles : traduites dans les 5 langues (blog.<locale>.yml articles.<slug>.faqs)
      + helper BlogHelper#blog_article_faqs (repli FR du contrôleur) ; show.html.erb lit le helper.
      Vérif : schema FAQPage rendu dans la bonne langue sur les 6 versions des 2 articles

### Phase 5 — Tests & validation ✅
- [x] Tests : changement de langue (LocaleController), fallback FR, persistance du choix
      (test/controllers/locale_controller_test.rb : langue valide en session + appliquée,
       langue invalide ignorée -> fallback FR, persistance sur le compte connecté, 5 runs)
- [x] Tests : story.locale (déjà couverts) — modèle (story_test.rb:93 défaut "fr")
      + controller (stories_controller_test.rb:208 create ?locale=en enregistre "en")
- [x] Suite complète verte : 231 runs, 0 failures
- [x] Précompilation assets OK (RAILS_ENV=test assets:precompile)

### Points d'attention
- Le bloc interactif [CHOIX] est parsé par mots-clés FR -> à sécuriser en Phase 2
- Coût API : traduire l'UI est gratuit ; générer des histoires dans 6 langues ne change
  pas le coût unitaire (1 histoire = 1 langue)
- Recommandation : livrer Phase 0 + 1 + 2 sur FR/EN d'abord, valider le rendu, PUIS
  dérouler Phase 3. Phase 4 (SEO) à traiter comme un projet distinct.
