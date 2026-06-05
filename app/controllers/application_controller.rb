class ApplicationController < ActionController::Base
  # ============================================================
  # Redirection www — noctilio-app.fr → www.noctilio-app.fr (301)
  # Les deux domaines sont actifs sur Railway, on canonicalise sur www
  # avant_action en premier pour que ça s'applique à toutes les requêtes
  # ============================================================
  before_action :redirect_to_www

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
  def after_sign_in_path_for(_resource)
    dashboard_path
  end

  private

  # Redirige noctilio-app.fr (sans www) vers www.noctilio-app.fr
  # 301 = redirection permanente — Google transfère le jus SEO vers le domaine canonique
  # Uniquement en production pour ne pas gêner le développement local
  def redirect_to_www
    return unless Rails.env.production? && request.host == "noctilio-app.fr"

    redirect_to "https://www.noctilio-app.fr#{request.fullpath}", status: :moved_permanently
  end

  # Calcule la phase lunaire actuelle en heure de Paris (UTC+1 ou UTC+2 selon DST)
  # Retourne un float entre 0.0 et 1.0 :
  #   0.0 / 1.0 = nouvelle lune
  #   0.25      = premier quartier (croissant → demi-lune droite)
  #   0.5       = pleine lune
  #   0.75      = dernier quartier (demi-lune gauche)
  # Disponible dans tous les controllers qui en ont besoin (dashboard, landing…)
  def current_moon_phase
    # Nouvelle lune de référence connue et précise : 6 janvier 2000 à 18h14 UTC
    # Source : US Naval Observatory
    reference_new_moon = Time.utc(2000, 1, 6, 18, 14, 0)

    # Période synodique (durée d'un cycle complet lune → lune) en secondes
    synodic_period_seconds = 29.530588853 * 24 * 3600

    # Temps actuel en UTC (même référentiel que la nouvelle lune de référence)
    now_utc = Time.now.utc

    # Nombre de secondes écoulées depuis la nouvelle lune de référence
    elapsed = now_utc - reference_new_moon

    # Phase = position dans le cycle, ramenée entre 0.0 et 1.0
    # modulo gère les cycles multiples depuis l'an 2000
    phase = (elapsed % synodic_period_seconds) / synodic_period_seconds

    phase.round(4) # 4 décimales suffisent pour l'affichage
  end

  # Vérifie que l'utilisateur peut encore créer des histoires ce mois-ci
  # Gratuit : 3 histoires max / mois — Pour l'instant tout le monde peut créer
  # (Stripe sera configuré plus tard)
  def check_story_limit!
    return if current_user.can_create_story?

    redirect_to stories_path, alert: "Vous avez atteint votre limite de 3 histoires gratuites ce mois-ci."
  end
end
