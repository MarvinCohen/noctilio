# ============================================================
# Job InactiveUserReminderJob — relance des comptes sans histoire
# ============================================================
# Planifié une fois par jour (config/recurring.yml, 10h Europe/Paris).
# Objectif rétention : un parent s'inscrit mais ne crée jamais sa première
# histoire. On le relance en douceur à J+7 puis à J+30.
#
# Anti-doublon SANS colonne de suivi en base :
#   Le job cible, pour chaque étape, les comptes créés EXACTEMENT ce jour-là
#   (fenêtre d'un jour calendaire = "il y a 7 jours" / "il y a 30 jours").
#   Comme le job tourne une seule fois par jour, un compte donné ne traverse
#   la fenêtre "J+7" qu'un seul jour, puis la fenêtre "J+30" un seul jour :
#   chaque relance n'est donc envoyée qu'une fois. Pas besoin de migration.
# ============================================================
class InactiveUserReminderJob < ApplicationJob
  queue_as :default

  # Étapes de relance, en jours depuis l'inscription.
  # Le mailer adapte son message selon l'étape (7 = léger, 30 = plus incitatif).
  REMINDER_STAGES = [7, 30].freeze

  def perform
    # On traite chaque étape indépendamment (J+7 puis J+30).
    REMINDER_STAGES.each { |stage| remind_stage(stage) }
  end

  private

  # Relance tous les comptes éligibles pour une étape donnée (7 ou 30 jours).
  def remind_stage(stage)
    # Fenêtre d'exactement `stage` jours : tous les comptes créés CE jour-là.
    # beginning_of_day..end_of_day borne la journée calendaire complète.
    day    = stage.days.ago
    window = day.beginning_of_day..day.end_of_day

    # find_each parcourt les users par lots (par défaut 1000) pour ne pas charger
    # toute la table en mémoire si beaucoup de comptes tombent dans la fenêtre.
    User.where(created_at: window).find_each do |user|
      # On ne relance QUE les comptes n'ayant créé AUCUNE histoire.
      # first_story_pending? = stories.none? (défini sur le modèle User).
      next unless user.first_story_pending?

      # deliver_later : l'envoi part dans la file Solid Queue (n'immobilise pas ce job).
      UserMailer.no_story_reminder(user, stage).deliver_later
    end
  end
end
