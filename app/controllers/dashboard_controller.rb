class DashboardController < ApplicationController
  # ============================================================
  # Controller du dashboard principal
  # ============================================================
  # Page d'accueil après connexion — vue d'ensemble pour l'utilisateur

  # GET /dashboard — page d'accueil de l'utilisateur connecté
  def index
    # Dernières histoires terminées (max 5 pour la section "Reprendre")
    @recent_stories = current_user.stories.completed_recent.limit(5)

    # Histoires en cours de génération (affiche une alerte si en cours)
    @pending_stories = current_user.stories.where(status: [:pending, :generating])

    # Profils enfants de l'utilisateur
    @children = current_user.children.ordered

    # Nombre d'histoires créées ce mois (pour afficher la limite gratuite)
    @stories_this_month = current_user.stories_this_month

    # Phase lunaire réelle (0.0 = nouvelle lune, 0.5 = pleine lune)
    # Passée à la vue pour dessiner la lune correctement sur le canvas
    @moon_phase = current_moon_phase
  end

  private

  # Calcule la phase lunaire actuelle en heure de Paris (UTC+1 ou UTC+2 selon DST)
  # Retourne un float entre 0.0 et 1.0 :
  #   0.0 / 1.0 = nouvelle lune
  #   0.25      = premier quartier (croissant → demi-lune droite)
  #   0.5       = pleine lune
  #   0.75      = dernier quartier (demi-lune gauche)
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
end
