# ============================================================
# AdminStats — objet de calcul des statistiques d'usage (admin)
# ============================================================
# Ce n'est PAS un modèle ActiveRecord : c'est un PORO (Plain Old Ruby Object)
# qui regroupe toutes les agrégations affichées sur le dashboard /admin.
#
# Pourquoi un objet dédié plutôt que du code dans le controller ?
#   - Fat Model / Skinny Controller : la logique de calcul est testable
#     unitairement (test/models/admin_stats_test.rb) sans passer par une requête HTTP.
#   - Chaque classement utilise UNE seule requête SQL `group(...).count`
#     (agrégation côté base) → aucun N+1, même avec beaucoup d'histoires.
#
# Convention : les méthodes de "classement" renvoient un tableau de paires
#   [[clé, nombre], ...] TRIÉ du plus fréquent au moins fréquent, pour que la
#   vue n'ait qu'à itérer et calculer des pourcentages.
class AdminStats
  # ============================================================
  # SECTION 1 — Vue d'ensemble (compteurs clés)
  # ============================================================
  # Renvoie un hash de compteurs simples affichés en haut du dashboard.
  def overview
    {
      users_total:          User.count,                       # tous les comptes
      admins:               User.where(admin: true).count,    # comptes administrateurs
      active_subscriptions: active_subscriptions_count,       # abonnements Stripe actifs (Pay)
      children_total:       Child.count,                      # profils enfants créés
      stories_total:        Story.count,                      # toutes les histoires
      stories_completed:    Story.completed.count,            # histoires générées avec succès
      stories_failed:       Story.where(status: :failed).count, # générations en échec
      failure_rate:         failure_rate                      # % d'échec (voir plus bas)
    }
  end

  # ============================================================
  # SECTION 2 — Préférences histoires (classements)
  # ============================================================

  # Univers choisis. La clé nil correspond au "thème libre" (custom_theme) :
  # on la garde car c'est une préférence à part entière. La vue traduira nil → "Thème libre".
  def world_themes
    sorted(Story.group(:world_theme).count)
  end

  # Valeurs éducatives choisies. On exclut nil (champ optionnel non renseigné)
  # pour ne pas polluer le classement avec un "non choisi".
  def educational_values
    sorted(Story.where.not(educational_value: nil).group(:educational_value).count)
  end

  # Styles d'illustration choisis (champ optionnel → on exclut nil).
  def image_styles
    sorted(Story.where.not(image_style: nil).group(:image_style).count)
  end

  # Durées demandées (5, 10 ou 15 min ; champ optionnel → on exclut nil).
  def durations
    sorted(Story.where.not(duration_minutes: nil).group(:duration_minutes).count)
  end

  # ============================================================
  # SECTION 3 — Mode interactif & choix
  # ============================================================

  # Répartition interactif vs classique → { true => n, false => m }.
  # group(:interactive) agrège côté base sur la colonne booléenne.
  def interactive_split
    Story.group(:interactive).count
  end

  # Pourcentage d'histoires interactives parmi TOUTES les histoires (0 à 100).
  # Garde anti-division par zéro : 0 % si aucune histoire.
  def interactive_percentage
    total = Story.count
    return 0 if total.zero?

    interactive = interactive_split[true] || 0
    (interactive * 100.0 / total).round
  end

  # Répartition des choix DÉJÀ résolus entre l'option A et l'option B
  # → { "a" => n, "b" => m }. On ne compte que les choix résolus (scope `resolved`).
  def choice_split
    StoryChoice.resolved.group(:chosen_option).count
  end

  # Taux de résolution des choix interactifs : part des choix où l'enfant a
  # effectivement décidé, sur l'ensemble des choix proposés (0 à 100).
  def choice_resolution_rate
    total = StoryChoice.count
    return 0 if total.zero?

    (StoryChoice.resolved.count * 100.0 / total).round
  end

  private

  # Trie un hash {clé => nombre} en tableau de paires, du plus grand au plus petit.
  # -count : tri décroissant (le plus fréquent en tête).
  def sorted(counts_hash)
    counts_hash.sort_by { |_key, count| -count }
  end

  # Taux d'échec : part des générations en échec parmi celles qui se sont TERMINÉES
  # (succès + échec). On exclut volontairement pending/generating, qui ne sont pas
  # encore "jugeables". Garde anti-division par zéro.
  def failure_rate
    completed = Story.completed.count
    failed    = Story.where(status: :failed).count
    finished  = completed + failed
    return 0 if finished.zero?

    (failed * 100.0 / finished).round
  end

  # Nombre d'abonnements Stripe actifs, via le gem Pay.
  # Pay::Subscription.active est le scope standard des abonnements en cours.
  def active_subscriptions_count
    Pay::Subscription.active.count
  end
end
