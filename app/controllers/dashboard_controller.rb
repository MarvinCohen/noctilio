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

    # --- Données de la carte "rituel du soir" (Fat Model : tout vient du modèle) ---
    # Niveau actuel + avancement vers le niveau suivant (pour l'orbe et la barre XP)
    @level          = current_user.level
    @level_progress = current_user.level_progress
    @xp_to_next     = current_user.xp_to_next_level

    # Nombre de trophées obtenus — affiché à côté de la progression
    @badges_count = current_user.user_badges.count

    # Constellation des 7 derniers soirs (étoiles allumées = soirs avec une histoire)
    # Habitude douce, jamais punitive : on valorise sans culpabiliser les soirs manqués.
    @constellation = current_user.recent_story_nights(7)

    # Histoire suggérée "du soir" : la dernière commencée mais non terminée si elle
    # existe, sinon la plus récente terminée (pour la relire d'un seul tap).
    @suggested_story = @recent_stories.first
  end

  # current_moon_phase est défini dans ApplicationController
  # et partagé avec PagesController (landing page)
end
