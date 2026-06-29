class ParentalController < ApplicationController
  # ============================================================
  # Controller du dashboard parental
  # ============================================================
  # Statistiques de lecture pour les parents

  # GET /parental — statistiques et gestion des enfants
  def index
    @children = current_user.children.ordered

    # IDs des enfants — réutilisés dans plusieurs requêtes pour éviter les doublons
    child_ids = @children.pluck(:id)

    # Temps de lecture total (approximation : durée choisie à la création)
    @total_reading_minutes = current_user.stories
                                         .completed
                                         .sum(:duration_minutes)

    # 5 dernières histoires terminées — pour le bloc "Activité récente"
    # includes(:child) pour éviter le N+1 lors de l'affichage du nom de l'enfant
    @recent_stories = current_user.stories
                                  .completed
                                  .recent
                                  .limit(5)
                                  .includes(:child)

    # Dernière histoire complétée par enfant (hash { child_id => story })
    # Utilisé dans la liste des héros pour afficher la date de dernière activité
    # .limit borne la requête — sans ça, tous les objets seraient chargés en mémoire
    last_completed = Story.completed
                          .where(child_id: child_ids)
                          .order(created_at: :desc)
                          .limit(child_ids.size * 10)
    @last_story_by_child = last_completed.group_by(&:child_id).transform_values(&:first)

    # IDs des enfants ayant au moins un choix interactif en attente
    # Un choix est "en attente" si chosen_option est nil (l'enfant n'a pas encore choisi)
    @children_with_pending = Story
                             .joins(:story_choices)
                             .where(child_id: child_ids,
                                    story_choices: { chosen_option: nil })
                             .distinct
                             .pluck(:child_id)

    # Valeurs éducatives explorées — regroupées par valeur, triées par fréquence
    # Exclut les histoires sans valeur éducative définie
    @educational_values = current_user.stories
                                      .completed
                                      .where.not(educational_value: [nil, ""])
                                      .group(:educational_value)
                                      .order("count_all DESC")
                                      .count

    # Histoires par jour sur les 30 derniers jours — pour la grille d'activité
    # stories_per_day retourne un hash { Date => count }, ex: { 2026-04-07 => 2, ... }
    @weekly_stories = stories_per_day(30)

    # Total d'histoires créées cette semaine (pour afficher le quota gratuit hebdomadaire)
    @stories_this_week = current_user.stories_this_week

    # Nombre d'histoires terminées PAR enfant, en UNE seule requête groupée.
    # Avant : la vue appelait child.stories.completed.count dans la boucle des
    # héros (1 requête SQL par enfant = N+1). On récupère un hash
    # { child_id => count } d'un coup, et la vue lit @completed_counts[child.id].
    @completed_counts = current_user.stories.completed.group(:child_id).count

    # Total d'histoires terminées — pour la carte de stats globale.
    # On le DÉRIVE de @completed_counts (somme des valeurs) plutôt que de relancer
    # un current_user.stories.completed.count dans la vue : zéro requête SQL en plus,
    # et la logique sort enfin du template (skinny controller).
    @completed_stories_count = @completed_counts.values.sum

    # Nombre d'enfants — réutilise child_ids déjà chargé (aucune requête COUNT
    # supplémentaire, contrairement à @children.count appelé dans la vue).
    @children_count = child_ids.size
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
