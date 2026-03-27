class ApplicationController < ActionController::Base
  # ============================================================
  # Authentification — toutes les pages nécessitent une connexion
  # sauf celles qui utilisent skip_before_action
  # ============================================================
  before_action :authenticate_user!

  # ============================================================
  # Redirection après connexion Devise
  # ============================================================
  # Par défaut Devise redirige vers root_path après connexion.
  # On surcharge cette méthode pour rediriger vers le dashboard.
  def after_sign_in_path_for(resource)
    dashboard_path
  end

  private

  # Vérifie que l'utilisateur peut encore créer des histoires ce mois-ci
  # Gratuit : 3 histoires max / mois — Pour l'instant tout le monde peut créer
  # (Stripe sera configuré plus tard)
  def check_story_limit!
    return if current_user.can_create_story?

    redirect_to stories_path, alert: "Vous avez atteint votre limite de 3 histoires gratuites ce mois-ci."
  end
end
