class Users::RegistrationsController < Devise::RegistrationsController
  # ============================================================
  # Controller d'inscription personnalisé
  # ============================================================
  # On surcharge le controller Devise de base pour deux raisons :
  # 1. Autoriser les champs supplémentaires : first_name et last_name
  # 2. Rediriger vers le dashboard après inscription (pas la page d'accueil)

  # Surcharge before_action pour autoriser nos champs personnalisés
  # Devise filtre les paramètres pour la sécurité — il faut explicitement
  # lui dire quels champs supplémentaires accepter
  before_action :configure_sign_up_params,   only: [:create]
  before_action :configure_account_update_params, only: [:update]

  # ============================================================
  # Redirection après inscription réussie
  # ============================================================
  # Par défaut Devise redirige vers root_path.
  # On redirige vers le dashboard après la création du compte.
  def after_sign_up_path_for(resource)
    dashboard_path
  end

  # Redirection après mise à jour du compte
  def after_update_path_for(resource)
    dashboard_path
  end

  protected

  # Ajoute first_name et last_name aux paramètres autorisés lors de l'inscription
  # sanitize_params est le mécanisme de Devise pour gérer les paramètres autorisés
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name])
  end

  # Ajoute first_name et last_name aux paramètres autorisés lors de la mise à jour
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name])
  end
end
