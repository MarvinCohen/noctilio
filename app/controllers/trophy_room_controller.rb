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

    # Niveau calculé : 1 niveau tous les 500 XP
    @level = (@xp_points / 500) + 1

    # Progression vers le prochain niveau (pourcentage)
    @level_progress = ((@xp_points % 500) / 500.0 * 100).round

    # Galerie des illustrations générées (dernières histoires avec image)
    @illustrated_stories = current_user.stories
                                       .completed
                                       .where.not(cover_image_url: nil)
                                       .recent
                                       .limit(9)
  end
end
