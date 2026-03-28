class ParentalController < ApplicationController
  # ============================================================
  # Controller du dashboard parental
  # ============================================================
  # Statistiques de lecture pour les parents

  # GET /parental — statistiques et gestion des enfants
  def index
    @children = current_user.children.ordered

    # Temps de lecture total (approximation : durée choisie à la création)
    @total_reading_minutes = current_user.stories
                                         .completed
                                         .sum(:duration_minutes)

    # Histoires par semaine pour le graphique (7 derniers jours)
    @weekly_stories = stories_per_day(7)

    # Thèmes favoris (world_theme le plus choisi)
    @favorite_themes = current_user.stories
                                   .completed
                                   .group(:world_theme)
                                   .order("count_all DESC")
                                   .limit(3)
                                   .count

    # Total d'histoires créées ce mois-ci (pour afficher la limite)
    @stories_this_month = current_user.stories_this_month
  end

  private

  # Retourne le nombre d'histoires créées par jour sur les N derniers jours
  # Utilisé pour le graphique de lecture hebdomadaire
  def stories_per_day(days)
    start_date = days.days.ago.beginning_of_day

    # Groupe les histoires par jour et compte
    # IMPORTANT : on qualifie "created_at" avec "stories." pour éviter l'ambiguïté
    # PostgreSQL ne sait pas choisir entre stories.created_at et children.created_at
    # car current_user.stories fait une jointure INNER JOIN avec la table children
    current_user.stories
                .where(stories: { created_at: start_date.. })
                .group("DATE(stories.created_at)")
                .order("DATE(stories.created_at)")
                .count
  end
end
