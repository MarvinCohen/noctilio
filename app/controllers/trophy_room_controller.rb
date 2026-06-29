class TrophyRoomController < ApplicationController
  # ============================================================
  # Controller de la salle des trophées
  # ============================================================
  # Affiche les badges gagnés, les XP et la progression de l'utilisateur

  # GET /trophees — page trophées
  def index
    # Tous les badges possibles (pour montrer ceux non encore gagnés en grisé)
    @all_badges = Badge.all

    # Badges déjà gagnés par l'utilisateur (avec date d'obtention)
    @earned_user_badges = current_user.user_badges.includes(:badge).order(earned_at: :desc)
    @earned_badge_ids   = @earned_user_badges.map(&:badge_id)

    # Points d'expérience et niveau calculés depuis le modèle User
    @xp_points = current_user.xp_points

    # Niveau (1 tous les 500 XP) — calculé dans le modèle User#level
    @level = current_user.level

    # Progression vers le prochain niveau (pourcentage)
    @level_progress = ((@xp_points % 500) / 500.0 * 100).round

    # Galerie des illustrations générées (dernières histoires avec image).
    # with_illustration : inclut AUSSI les images gpt-image-1 attachées via
    # ActiveStorage (qui n'écrivent pas cover_image_url) — l'ancien filtre
    # where.not(cover_image_url: nil) les excluait à tort.
    # includes(:child) : évite le N+1 sur story.child.name dans la vue.
    # with_attached_cover_image : précharge les blobs ActiveStorage en une requête
    # pour éviter un N+1 sur chaque image_tag story.cover_image de la galerie.
    @illustrated_stories = current_user.stories
                                       .completed
                                       .with_illustration
                                       .recent
                                       .limit(9)
                                       .includes(:child)
                                       .with_attached_cover_image
  end
end
