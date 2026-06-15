class DashboardController < ApplicationController
  # ============================================================
  # Controller du dashboard principal
  # ============================================================
  # Page d'accueil après connexion — vue d'ensemble pour l'utilisateur

  # GET /dashboard — page d'accueil de l'utilisateur connecté
  def index
    # Dernières histoires terminées (max 5 pour la section "Reprendre")
    # includes(:child) précharge l'enfant associé en une requête — évite le N+1
    # quand la vue affiche le nom ou l'avatar de l'enfant pour chaque histoire
    # with_attached_cover_image précharge aussi les pièces jointes ActiveStorage
    # — évite le N+1 quand la vue affiche la couverture de chaque histoire
    @recent_stories = current_user.stories.completed_recent.includes(:child).with_attached_cover_image.limit(5)

    # Histoires en cours de génération — bornées à 10 pour éviter une requête non bornée
    # includes(:child) pour les mêmes raisons que @recent_stories
    @pending_stories = current_user.stories
                                   .where(status: %i[pending generating])
                                   .includes(:child)
                                   .limit(10)

    # Profils enfants de l'utilisateur
    @children = current_user.children.ordered

    # Nombre d'histoires créées cette semaine (pour afficher le quota gratuit hebdomadaire)
    @stories_this_week = current_user.stories_this_week

    # Phase lunaire réelle (0.0 = nouvelle lune, 0.5 = pleine lune)
    # Passée à la vue pour dessiner la lune correctement sur le canvas
    @moon_phase = current_moon_phase
  end

  # current_moon_phase est défini dans ApplicationController
  # et partagé avec PagesController (landing page)
end
