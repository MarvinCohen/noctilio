class ApplicationController < ActionController::Base
  # ============================================================
  # Authentification — toutes les pages nécessitent une connexion
  # sauf celles qui utilisent skip_before_action
  # ============================================================
  before_action :authenticate_user!

  # Protection CSRF (Cross-Site Request Forgery) — Rails l'active par défaut
  # Elle vérifie que les formulaires viennent bien de notre site

  private

  # Vérifie que l'utilisateur a un abonnement premium actif
  # À utiliser avec before_action dans les controllers qui ont du contenu premium
  def require_premium!
    return if current_user.premium?

    redirect_to subscription_path, alert: "Cette fonctionnalité est réservée aux membres Premium. Découvrez nos offres !"
  end

  # Vérifie que l'utilisateur peut encore créer des histoires ce mois-ci
  # Gratuit : 3 histoires max / mois — Premium : illimité
  def check_story_limit!
    return if current_user.can_create_story?

    redirect_to subscription_path, alert: "Vous avez atteint votre limite de 3 histoires gratuites ce mois-ci. Passez en Premium pour des histoires illimitées !"
  end
end
