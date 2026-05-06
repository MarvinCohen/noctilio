Rails.application.routes.draw do
  # ============================================================
  # Authentification Devise — gère inscription, connexion, etc.
  # ============================================================
  # controllers: indique à Devise d'utiliser notre controller personnalisé
  # pour les inscriptions (qui autorise first_name et last_name)
  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  # ============================================================
  # Page d'accueil publique (landing page)
  # ============================================================
  root to: "pages#home"

  # ============================================================
  # Liste d'attente — reçoit les emails de la landing page
  # ============================================================
  # POST /waitlist : sauvegarde un email en base et retourne JSON
  post "/waitlist", to: "waitlist#create", as: :waitlist

  # ============================================================
  # Dashboard principal — page d'accueil après connexion
  # ============================================================
  get "/dashboard",   to: "dashboard#index",     as: :dashboard

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
    end
  end

  # ============================================================
  # Dashboard parental — statistiques de lecture des enfants
  # ============================================================
  get "/parental",    to: "parental#index",      as: :parental

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

  # ============================================================
  # Admin — pages privées accessibles uniquement par marvincohen95@gmail.com
  # ============================================================
  # GET /admin/waitlist — liste des emails inscrits sur la waitlist
  get "/admin/waitlist", to: "admin#waitlist", as: :admin_waitlist

  # ============================================================
  # Pages légales — publiques, pas besoin d'être connecté
  # ============================================================
  get "/cgu",                   to: "pages#cgu",     as: :cgu
  get "/confidentialite",       to: "pages#privacy",  as: :privacy
  # Mentions légales — obligatoires en France pour tout site web commercial
  get "/mentions-legales",      to: "pages#legal",    as: :legal_notice

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
