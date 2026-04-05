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

  # current_moon_phase est défini dans ApplicationController
  # et partagé avec PagesController (landing page)
end
