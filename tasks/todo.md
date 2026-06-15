# ============================================================
# Offre découverte : 1re histoire en ACCÈS COMPLET
# ============================================================

## Objectif
La toute 1re histoire de chaque compte débloque l'expérience complète
(illustration IA + lecture audio + mode interactif), même pour un gratuit.
But : montrer toute la valeur dès la 1re histoire → donner envie de s'abonner.
À partir de la 2e histoire, le gratuit repasse en texte seul.

## Règle de détection
- Une histoire est "offerte" si c'est la 1re du compte = la plus petite id
  (stories.minimum(:id)). Simple, sans nouvelle colonne en base.
- Limite connue : si l'utilisateur SUPPRIME sa 1re histoire, la suivante
  redevient "la 1re" → re-offerte. Acceptable au lancement (faible risque).

## Fichiers impactés
- app/models/user.rb — 3 méthodes :
    - welcome_story?(story)      → story.id == stories.minimum(:id)
    - full_experience_for?(story)→ premium? || welcome_story?(story)
    - first_story_pending?       → stories.none? (pour le formulaire)
- app/jobs/generate_story_job.rb — remplacer `user.premium?` par
    `user.full_experience_for?(story)` (image + audio).
- app/controllers/stories_controller.rb — endpoint audio (l.225) :
    autoriser si `current_user.full_experience_for?(@story)`.
- app/views/stories/new.html.erb — toggle interactif activé si
    `current_user.premium? || current_user.first_story_pending?`.
- test/models/user_test.rb — couvrir les 3 nouvelles méthodes.

## Étapes
- [x] user.rb : ajouter welcome_story?, full_experience_for?, first_story_pending?
- [x] generate_story_job.rb : gate image+audio sur full_experience_for?(story)
- [x] stories_controller.rb : gate audio sur full_experience_for?(@story)
- [x] new.html.erb : toggle interactif ouvert pour la 1re histoire
- [x] new.html.erb : bannière d'offre "1re histoire offerte en accès complet"
- [x] _story_new.scss : style de la bannière (.wizard-offer-banner)
- [x] Tests modèle pour les 3 méthodes (8 tests ajoutés)
- [x] Suite complète verte (214 runs, 0 failures)

# ============================================================
# Mode gratuit = TEXTE SEUL (image + audio réservés au Premium)
# ============================================================

## Objectif
Le gratuit ne reçoit que le TEXTE de l'histoire. L'illustration IA (gpt-image-1)
et la lecture vocale (TTS) deviennent réservées au Premium. Double bénéfice :
réduit le coût (l'image est la partie chère) et rend le Premium clairement désirable.

## Fichiers impactés
- app/jobs/generate_story_job.rb — ne générer image + audio que si user.premium?
- app/views/subscriptions/index.html.erb — tableau comparatif : "Illustrations" gratuit → —
- app/models/user.rb — selon décision quota (voir question ci-dessous)
- app/controllers/stories_controller.rb — selon décision quota (check_story_limit!)
- test/jobs + test/models — couvrir le nouveau comportement

## Décisions
- Image : dans GenerateStoryJob, n'appeler ImageGeneratorService que si la story
  appartient à un user premium. Sinon, histoire = texte seul (la vue gère déjà
  l'absence de cover, show.html.erb:119).
- Audio : idem, ne lancer GenerateAudioJob que pour un premium (TTS payant + déjà
  réservé premium à la lecture).
- Le héros doit quand même être décrit dans le texte (pas de changement côté texte).

## QUESTION À TRANCHER (avant de coder)
Maintenant que l'image est le vrai différenciateur, le gratuit garde-t-il un quota
mensuel, ou passe-t-il en TEXTE ILLIMITÉ ?
  → Reco : texte illimité (supprime la frustration du "mur" des 3/mois ; le levier
    de conversion devient l'image/l'audio/l'interactif, pas un compteur).
  → Si on garde un quota : lequel (5/mois ? hebdo ?).

## Étapes (à valider après réponse)
- [ ] GenerateStoryJob : entourer image + audio d'un `if story.child.user.premium?`
- [ ] Tableau comparatif : "Illustrations générées par IA" gratuit ✓ → —
- [ ] Quota selon décision (illimité = retirer check_story_limit! / ajuster can_create_story?)
- [ ] Tests : free → pas d'image ni d'audio ; premium → image + audio
- [ ] Suite complète verte

# ============================================================
# Configuration Stripe (abonnement Premium 9,99 €/mois)
# ============================================================

## Constat
Le CODE est déjà complet, rien à écrire côté Rails :
- gem `pay` + `stripe` (Gemfile), initializer `config/initializers/pay.rb`
- `SubscriptionsController` (index / checkout / success / cancel)
- `User#premium?` branché sur Pay (`payment_processor.subscribed?`)
- routes `/abonnement*` + webhooks auto-montés sur `/pay/webhooks/stripe`
- tables `pay_*` déjà migrées
Configurer Stripe = créer le compte/produit côté Stripe + renseigner 4 variables d'env.

## Clés lues par Pay (ordre : ENV d'abord)
- STRIPE_PRIVATE_KEY    → clé secrète (sk_test_… puis sk_live_…)
- STRIPE_PUBLIC_KEY     → clé publiable (pk_test_… / pk_live_…)
- STRIPE_SIGNING_SECRET → secret de signature du webhook (whsec_…)
- STRIPE_PREMIUM_PRICE_ID → id du tarif récurrent (price_…) — utilisé dans le checkout

## Étapes — MODE TEST d'abord (aucun vrai paiement)
- [ ] Marvin : créer/activer le compte Stripe, rester en mode "Test"
- [ ] Marvin : Produits → créer "Noctilio Premium", tarif récurrent 9,99 €/mois → copier le price_id
- [ ] Marvin : Développeurs → Clés API → copier clé publiable (pk_test) + secrète (sk_test)
- [ ] Moi : ajouter les 4 placeholders STRIPE_* dans .env (Marvin colle les valeurs test)
- [ ] Webhook local : lancer `stripe listen --forward-to localhost:3000/pay/webhooks/stripe`
      → la commande affiche le whsec_… à mettre dans STRIPE_SIGNING_SECRET (.env)
- [ ] Redémarrer le serveur (relecture .env)
- [ ] Test bout-en-bout : /abonnement → "Passer Premium" → CB test 4242 4242 4242 4242
      → retour success → vérifier en console que `user.premium?` == true
- [ ] Tester la résiliation (POST cancel) → `subscription.cancel` (accès gardé jusqu'à l'échéance)
- [ ] Moi : documenter les 4 variables STRIPE_* dans CLAUDE.md

## Étapes — PASSAGE EN LIVE (le jour du lancement)
- [ ] Marvin : basculer Stripe en mode "Live", recréer le produit/price (live), copier price_id live
- [ ] Marvin : copier les clés live (pk_live / sk_live)
- [ ] Marvin : Webhooks → ajouter l'endpoint https://www.noctilio-app.fr/pay/webhooks/stripe
      → événements : checkout.session.completed, customer.subscription.* , invoice.* → copier le whsec live
- [ ] Marvin : poser les 4 variables STRIPE_* (valeurs live) sur Railway
- [ ] Réactiver les quotas (sinon le gratuit reste illimité) :
      décommenter `check_story_limit!` (stories_controller.rb) + réactiver le test associé

## Question avant de commencer
Tu as déjà ton compte Stripe accessible (mode test), ou je te guide pas à pas depuis zéro ?

# ============================================================
# Page de retours / feedback (option intégrée)
# ============================================================

## Objectif
Permettre aux visiteurs (connectés ou non) de laisser un retour (bug, suggestion,
autre) via une page dédiée. Les retours sont stockés en base et consultables par
l'admin. On reste simple : un modèle, un controller RESTful, une page publique,
une liste admin, un lien dans le footer.

## Fichiers impactés
- db/migrate/XXXX_create_feedbacks.rb (nouveau)
- app/models/feedback.rb (nouveau)
- app/controllers/feedbacks_controller.rb (nouveau, public)
- app/controllers/admin_controller.rb (ajout action feedbacks)
- app/views/feedbacks/new.html.erb (nouveau, formulaire)
- app/views/admin/feedbacks.html.erb (nouveau, liste admin)
- app/views/shared/_footer.html.erb (lien "Donner mon avis")
- config/routes.rb (routes /avis + /admin/feedbacks)
- test/models/feedback_test.rb (nouveau)
- test/controllers/feedbacks_controller_test.rb (nouveau)
- test/controllers/admin_controller_test.rb (ajout : feedbacks réservé admin)

## Décisions
- Champs : message (obligatoire), email (optionnel), category (bug/suggestion/autre),
  page_url (page d'origine, optionnel), user_id (optionnel, rempli si connecté).
- Anti-spam : champ honeypot caché (rempli par les bots → on ignore en silence).
- Page publique : skip_before_action :authenticate_user! sur feedbacks (comme les
  pages légales). Si l'utilisateur est connecté, on pré-remplit email + user_id.
- Liste admin : réutilise require_admin! du AdminController existant.
- SEO : la page reste noindex (comportement par défaut de l'app), pas dans le sitemap.

## Étapes
- [x] Migration create_feedbacks (message:text, email, category, page_url, references user nullable)
- [x] db:migrate
- [x] Modèle Feedback : belongs_to :user optional, validations (message présent, longueur), constante CATEGORIES
- [x] FeedbacksController#new (skip auth, formulaire) + #create (honeypot, pré-remplissage si connecté, flash de remerciement)
- [x] AdminController#feedbacks (liste triée, protégée par require_admin!)
- [x] Routes : get/post "/avis" + get "/admin/feedbacks"
- [x] Vue feedbacks/new : formulaire (message, email, catégorie) + honeypot + style cohérent
- [x] Vue admin/feedbacks : tableau des retours (date, catégorie, message, email, user)
- [x] Lien "Donner mon avis" dans le footer
- [x] Tests modèle + controller + accès admin
- [x] Suite complète verte (206 runs, 0 failures)

# ============================================================
# Refonte image : approche "Portrait du héros" (branche feature/image-portrait)
# ============================================================

## Objectif (image)
L'enfant doit SE RECONNAÎTRE sur l'illustration pour s'identifier au héros au coucher.
On passe d'un prompt "scène d'action épique" (perso minuscule, mal cadré) à un PORTRAIT
centré, visage visible, monde de l'histoire en arrière-plan doux. On simplifie aussi le
pipeline : prompt construit en Ruby (déterministe), sans appel Groq intermédiaire.

## Fichiers impactés (image)
- app/models/child.rb — meilleure traduction couleurs (cheveux/yeux/peau)
- app/services/image_generator_service.rb — nouveau build_image_prompt portrait + nettoyage
- app/services/story_generator_service.rb — suppression de generate_image_scene_prompt
- app/jobs/generate_story_job.rb — suppression de l'étape Groq image_scene_prompt
- app/assets/stylesheets/pages/_stories.scss — cadrage portrait (déjà ajusté)

## Étapes (image)
- [x] child.rb : tables de traduction cheveux/yeux/peau + image_description = clause portrait
- [x] image_generator_service.rb : build_image_prompt déterministe (portrait + décor + style)
- [x] image_generator_service.rb : supprimer code mort (ACTION_KEYWORDS, PILOT_KEYWORDS, extract_key_moment, STYLE_KEYWORDS, VISUAL_STYLE*)
- [x] image_generator_service.rb : négatifs "elderly/adult" sur le chemin fal.ai
- [x] story_generator_service.rb : supprimer generate_image_scene_prompt
- [x] generate_story_job.rb : retirer l'appel Groq image_scene, garder reload + ImageGeneratorService
- [x] Suite de tests (186 runs, 0 failures)
- [ ] Régénérer une image de test pour comparer le rendu

# ============================================================
# (Ancien plan — commercialisation, terminé)
# ============================================================

## Objectif

Préparer Noctilio à la commercialisation (hors quotas — gardés désactivés pour les
tests de Marvin). Ordre : sécurité serveur → RGPD → dashboard → page abonnement.

## Étapes

### 1. Gardes serveur (protection du modèle premium)
- [x] story.rb : validation serveur — interactive: true exige un compte premium
      (la checkbox HTML désactivée ne suffit pas, contournable via POST direct)
- [x] stories_controller.rb#audio : exiger premium? (le TTS coûte de l'argent à chaque appel)

### 2. RGPD (obligatoire — données de mineurs)
- [x] Vérifier les associations dependent: :destroy (User → Children → Stories → attachments)
- [x] Bouton "Supprimer mon compte" dans /mon-compte (Devise registrations#destroy + confirmation)
- [x] Case consentement parental obligatoire à la création d'un profil enfant
      (attribut virtuel + validates acceptance)

### 3. Dashboard utile (au lieu de la landing dupliquée)
- [x] Retirer les sections marketing (Comment ça marche / Fonctionnalités / Témoignages)
- [x] Ajouter : dernières histoires (reprendre la lecture) + raccourci enfants

### 4. Page abonnement plus vendeuse
- [x] Tableau comparatif Gratuit vs Premium
- [x] Mini FAQ (facturation, annulation)

### 5. Tests des protections (régression)
- [x] story_test.rb : validation interactive_requires_premium (4 cas : gratuit refusé,
      premium accepté, non-interactif ok, histoire existante reste valide)
- [x] child_test.rb : consentement parental (décoché refusé, coché ok, nil ok, update ok)
- [x] stories_controller_test.rb : POST interactive forgé → 422, audio gratuit → 403
- [x] account_controller_test.rb : page protégée + mode test réservé à la liste blanche

### 6. Analytics — Umami Cloud (gratuit, cookieless)
Décision : Umami Cloud (compte gratuit sur cloud.umami.is, jusqu'à 10k events/mois).
Comportement : script rendu seulement si ENV["UMAMI_WEBSITE_ID"] présent (→ off en dev/test),
jamais pour un admin connecté (n'pollue pas les stats avec le mode test), cookieless (pas de bannière RGPD).

- [x] CSP : autoriser cloud.umami.is dans script_src + connect_src
- [x] AnalyticsHelper#umami_enabled? (ENV présent ET pas admin connecté)
- [x] Partial shared/_analytics.html.erb (balise <script defer> conditionnelle, avec nonce)
- [x] Inclure le partial dans le <head> des layouts application + landing
- [x] Documenter UMAMI_WEBSITE_ID dans CLAUDE.md (projet)
- [x] Test analytics_helper_test.rb (activation/désactivation selon ENV + admin)
- [ ] À faire par Marvin : créer le site sur cloud.umami.is, mettre UMAMI_WEBSITE_ID sur Railway

## Checklist de lancement (jour J)
- [ ] Réactiver les quotas : décommenter check_story_limit! (stories_controller.rb:12-14)
      + réactiver le test "limite mensuelle" désactivé dans stories_controller_test.rb
- [ ] Stripe : créer le produit Premium 9,99€/mois + STRIPE_PREMIUM_PRICE_ID sur Railway
      (mode test d'abord, puis basculer en mode live)
- [ ] Stripe : tester le flux complet checkout → webhook → premium? = true → résiliation
- [ ] Retirer ou vider AUTHORIZED_TEST_EMAILS si le mode test ne doit plus servir en prod
- [ ] Analytics : choisir Plausible (payant, simple) ou Umami (gratuit, auto-hébergé Railway)
- [ ] Vérifier robots.txt / sitemap.xml / Schema.org (voir section dédiée dans CLAUDE.md
      si la landing est remplacée par le dashboard)
- [ ] Tester l'inscription complète en prod : signup → enfant (consentement) → histoire
- [ ] Vérifier les emails Devise en prod (confirmation, reset password)

## Notes
- Quotas (check_story_limit!) : volontairement laissés désactivés — tests en cours
- Analytics : nécessite un compte externe (Plausible/Umami) — à décider avec Marvin
