# ============================================================
# Job EveningStoryReminderJob — rappel "histoire du soir" (rétention douce)
# ============================================================
# Planifié chaque soir à 19h30 (Europe/Paris) via config/recurring.yml.
# Anti-spam (règle validée) : on ne notifie QUE les comptes qui :
#   1. ont au moins un abonnement push actif (opt-in), ET
#   2. n'ont PAS créé d'histoire depuis 3 jours (ou jamais).
# Un parent qui crée des histoires régulièrement n'est donc jamais dérangé.
# ============================================================
class EveningStoryReminderJob < ApplicationJob
  queue_as :default

  # Seuil d'inactivité avant de relancer (en jours).
  INACTIVITY_THRESHOLD = 3.days

  def perform
    # On ne parcourt que les utilisateurs réellement abonnés au push (opt-in).
    # distinct : un user avec plusieurs appareils ne ressort qu'une fois.
    User.joins(:push_subscriptions).distinct.find_each do |user|
      next unless inactive_enough?(user)

      send_reminder_to(user)
    end
  end

  private

  # true si l'utilisateur n'a créé aucune histoire dans les 3 derniers jours
  # (ou n'en a jamais créé). maximum(:created_at) renvoie nil si aucune histoire.
  def inactive_enough?(user)
    last_story_at = user.stories.maximum(:created_at)
    last_story_at.nil? || last_story_at < INACTIVITY_THRESHOLD.ago
  end

  # Envoie la notification à tous les appareils abonnés de l'utilisateur.
  def send_reminder_to(user)
    title = "Une petite histoire ce soir ?"
    body  = reminder_body(user)

    # On recharge la liste à chaque appareil : un abonnement expiré est supprimé
    # par le service au fil de l'eau, d'où l'usage de to_a pour figer la liste.
    user.push_subscriptions.to_a.each do |subscription|
      PushNotificationService.new(subscription).deliver(
        title: title,
        body:  body,
        url:   "/stories/new" # le clic ouvre directement la création d'histoire
      )
    end
  end

  # Personnalise le message avec le prénom d'un enfant s'il y en a un.
  def reminder_body(user)
    child = user.children.first
    if child
      "#{child.name} attend sa prochaine aventure ✦"
    else
      "Offre un moment magique à ton enfant avant le dodo ✦"
    end
  end
end
