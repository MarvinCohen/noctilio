Rails.application.routes.draw do
  # ============================================================
  # Authentification Devise — gère inscription, connexion, etc.
  # ============================================================
  # controllers: indique à Devise d'utiliser notre controller personnalisé
  # pour les inscriptions (qui autorise first_name et last_name)
  devise_for :users, controllers: {
    registrations:      "users/registrations",
    # omniauth_callbacks : notre controller qui gère le retour de Google
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  # ============================================================
  # PAGES PUBLIQUES MULTILINGUES (SEO) — préfixe de langue dans l'URL
  # ============================================================
  # scope "(:locale)" : le segment :locale est OPTIONNEL (parenthèses).
  #   - Sans préfixe  -> français (langue par défaut, pas de /fr/ dans l'URL)
  #   - Avec préfixe  -> /en/…, /es/…, /de/…, /it/…, /pt/… (5 autres langues)
  # La contrainte locale: /en|es|de|it|pt/ EXCLUT volontairement "fr" :
  #   ainsi le français n'a jamais de préfixe (URL canonique propre) et une URL
  #   comme /fr/blog ne matche pas (évite le contenu dupliqué fr vs /fr/).
  # On enveloppe UNIQUEMENT les pages publiques indexées par Google. L'app privée
  # (dashboard, histoires…) reste sans préfixe : elle est en noindex, le SEO
  # multilingue ne la concerne pas.
  scope "(:locale)", locale: /en|es|de|it|pt/ do
    # Page d'accueil publique (landing page)
    root to: "pages#home"

    # Page À propos — présente Marvin Cohen, fondateur de Noctilio (signaux E-E-A-T)
    get "/a-propos", to: "pages#a_propos", as: :a_propos

    # Pages légales — publiques, obligatoires en France (LCEN 2004)
    get "/cgu",              to: "pages#cgu",     as: :cgu
    get "/confidentialite",  to: "pages#privacy", as: :privacy
    get "/mentions-legales", to: "pages#legal",   as: :legal_notice

    # Blog — articles SEO publics (vues ERB, pas de base de données)
    # Chaque slug correspond à app/views/blog/_<slug>.html.erb
    get "/blog",       to: "blog#index", as: :blog
    get "/blog/:slug", to: "blog#show",  as: :blog_post
  end

  # ============================================================
  # Liste d'attente — reçoit les emails de la landing page
  # ============================================================
  # POST /waitlist : sauvegarde un email en base et retourne JSON
  post "/waitlist", to: "waitlist#create", as: :waitlist

  # ============================================================
  # Home — page d'accueil après connexion (anciennement /dashboard)
  # ============================================================
  get "/home",   to: "dashboard#index",     as: :dashboard

  # ============================================================
  # Enfants — CRUD complet pour gérer les profils enfants
  # ============================================================
  resources :children

  # ============================================================
  # Histoires — création, lecture, suppression + actions spéciales
  # ============================================================
  resources :stories, only: [:index, :show, :new, :create, :destroy] do
    member do
      # POST /stories/:id/choose — soumettre un choix interactif
      post :choose

      # GET /stories/:id/status — polling du statut de génération (retourne JSON)
      get :status

      # POST /stories/:id/save_story — sauvegarder l'histoire dans la bibliothèque
      post :save_story

      # POST /stories/:id/audio — génère et retourne l'audio TTS (OpenAI)
      post :audio

      # POST /stories/:id/continue — crée un nouvel épisode suite à cette histoire
      post :continue

      # POST /stories/:id/replay — recrée la même histoire from scratch pour faire d'autres choix
      post :replay

      # POST /stories/:id/explore_alternative — génère la timeline alternative d'un choix
      post :explore_alternative

      # POST /stories/:id/retry — relance la génération d'une histoire échouée
      post :retry
    end
  end

  # ============================================================
  # Partage public d'une histoire — lecture seule, SANS authentification
  # ============================================================
  # Le :token est un jeton signé (voir Story#share_token) qui contient l'id
  # de l'histoire. Impossible à deviner ou à forger → on peut exposer cette
  # page publiquement sans risque qu'un visiteur lise les histoires des autres.
  get "/histoire/:token", to: "shared_stories#show", as: :shared_story

  # ============================================================
  # Dashboard parental — statistiques de lecture des enfants
  # ============================================================
  get "/parental",    to: "parental#index",      as: :parental

  # ============================================================
  # Mon compte — espace personnel : infos du compte + statut abonnement
  # ============================================================
  # GET /mon-compte — affiche les infos du compte connecté
  get  "/mon-compte",           to: "account#show",             as: :account
  # POST /mon-compte/mode-test — bascule le mode test (admin) pour débloquer
  # les fonctionnalités premium. Restreint à une liste blanche d'emails côté serveur.
  post "/mon-compte/mode-test", to: "account#toggle_test_mode", as: :account_toggle_test_mode
  # GET /mon-compte/export — télécharge toutes les données personnelles de
  # l'utilisateur au format JSON (droit d'accès / portabilité RGPD).
  get  "/mon-compte/export",    to: "account#export",           as: :account_export

  # ============================================================
  # Notifications push (PWA) — abonnement / désabonnement
  # ============================================================
  # POST   : enregistre l'abonnement du navigateur (rappel "histoire du soir")
  # DELETE : supprime l'abonnement de cet appareil
  # Pilotées par le Stimulus push_controller (page /mon-compte).
  post   "/push_subscriptions", to: "push_subscriptions#create",  as: :push_subscriptions
  delete "/push_subscriptions", to: "push_subscriptions#destroy"

  # ============================================================
  # Langue de l'interface — changement de langue (i18n)
  # ============================================================
  # POST /langue — enregistre la langue choisie (en session + sur le compte si
  # connecté) puis renvoie l'utilisateur sur la page d'où il vient. Utilisé par
  # le sélecteur de langue (shared/_locale_switcher).
  post "/langue", to: "locale#update", as: :locale

  # ============================================================
  # Salle des trophées — badges et XP de l'utilisateur
  # ============================================================
  get "/trophees",    to: "trophy_room#index",   as: :trophy_room

  # ============================================================
  # Pay::Engine — PAS besoin de monter manuellement !
  # Pay 7 se monte automatiquement via son initializer.
  # Les webhooks Stripe arrivent sur : /pay/webhooks/stripe
  # Configure cette URL dans ton dashboard Stripe (section Webhooks) !

  # ============================================================
  # Abonnements — page de tarification et gestion Stripe
  # ============================================================
  get  "/abonnement",          to: "subscriptions#index",   as: :subscription
  post "/abonnement/checkout", to: "subscriptions#checkout", as: :subscription_checkout
  get  "/abonnement/success",  to: "subscriptions#success",  as: :subscription_success
  post "/abonnement/cancel",   to: "subscriptions#cancel",   as: :subscription_cancel
  post "/abonnement/reactiver", to: "subscriptions#resume",   as: :subscription_resume

  # ============================================================
  # Admin — pages privées accessibles uniquement par marvincohen95@gmail.com
  # ============================================================
  # GET /admin — dashboard d'accueil admin (statistiques d'usage + liens vers
  # les autres pages admin). `as: :admin_root` génère le helper admin_root_path.
  get "/admin", to: "admin#index", as: :admin_root
  # GET /admin/waitlist — liste des emails inscrits sur la waitlist
  get "/admin/waitlist", to: "admin#waitlist", as: :admin_waitlist
  # GET /admin/feedbacks — liste des retours utilisateurs laissés via /avis
  get "/admin/feedbacks", to: "admin#feedbacks", as: :admin_feedbacks

  # ============================================================
  # Avis / retours — page publique pour laisser un retour (bug, suggestion...)
  # ============================================================
  # GET  /avis → formulaire ; POST /avis → enregistre le retour
  # Accessible sans connexion (skip_before_action dans FeedbacksController)
  get  "/avis", to: "feedbacks#new",    as: :feedback
  post "/avis", to: "feedbacks#create"

  # ============================================================
  # NB : les pages publiques multilingues (root, a-propos, légales, blog) sont
  # définies plus haut dans le bloc scope "(:locale)" pour le SEO multilingue.
  # ============================================================

  # ============================================================
  # Sitemap XML dynamique et multilingue
  # ============================================================
  # Un seul sitemap couvre toutes les langues (chaque page liste ses versions
  # linguistiques via hreflang). Remplace l'ancien public/sitemap.xml statique.
  # Hors scope "(:locale)" : le sitemap n'est pas une page traduite, c'est un
  # fichier unique référencé dans robots.txt.
  get "/sitemap.xml", to: "sitemaps#show", defaults: { format: "xml" }, as: :sitemap

  # ============================================================
  # Health check — vérifie que l'application fonctionne
  # ============================================================
  get "up" => "rails/health#show", as: :rails_health_check

  # ============================================================
  # PWA — manifest et service worker
  # ============================================================
  # Le manifest.json déclare l'app comme installable (nom, icône, couleurs)
  # Le service-worker.js gère le cache offline et les notifications push
  # Ces deux routes sont servies par le controller intégré Rails 8 (rails/pwa)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
