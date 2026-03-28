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
  # Webhooks Stripe — reçoit les événements de paiement
  # ============================================================
  namespace :webhooks do
    post "stripe", to: "stripe#create"
  end

  # ============================================================
  # Abonnements — page de tarification et gestion Stripe
  # ============================================================
  get "/abonnement",  to: "subscriptions#index", as: :subscription
  post "/abonnement/checkout", to: "subscriptions#checkout", as: :subscription_checkout

  # ============================================================
  # Health check — vérifie que l'application fonctionne
  # ============================================================
  get "up" => "rails/health#show", as: :rails_health_check
end
