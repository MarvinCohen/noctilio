require "test_helper"

# ============================================================
# Tests du job InactiveUserReminderJob (relance des comptes inactifs)
# ============================================================
# On vérifie la règle de ciblage : relancer UNIQUEMENT les comptes créés il y a
# exactement 7 ou 30 jours ET n'ayant créé aucune histoire. On ignore les comptes
# qui ont déjà une histoire, et ceux hors des fenêtres J+7 / J+30.
class InactiveUserReminderJobTest < ActiveJob::TestCase
  # Crée un utilisateur de test confirmé, avec une date d'inscription contrôlée.
  # created_at est explicitement posé pour placer le compte dans (ou hors) fenêtre.
  def creer_user(email:, created_at:)
    User.create!(
      first_name: "Test",
      last_name: "Relance",
      email: email,
      password: "motdepasse123",
      password_confirmation: "motdepasse123",
      confirmed_at: Time.current,
      created_at: created_at
    )
  end

  # Vérifie que perform relance J+7 et J+30 (sans histoire) et ignore les autres.
  test "perform relance les comptes J+7 et J+30 sans histoire, ignore les autres" do
    # Arrange
    # - compte créé il y a exactement 7 jours, sans histoire → doit être relancé
    creer_user(email: "j7@example.com", created_at: 7.days.ago)
    # - compte créé il y a exactement 30 jours, sans histoire → doit être relancé
    creer_user(email: "j30@example.com", created_at: 30.days.ago)
    # - compte J+7 mais AVEC une histoire → doit être ignoré (plus "inactif")
    j7_actif = creer_user(email: "j7actif@example.com", created_at: 7.days.ago)
    enfant   = j7_actif.children.create!(name: "Zoé", age: 5, gender: "girl")
    enfant.stories.create!(status: :pending)
    # - compte hors fenêtre (5 jours) → doit être ignoré
    creer_user(email: "hors@example.com", created_at: 5.days.ago)

    # On vide les emails de bienvenue enfilés à la création des comptes,
    # pour n'observer que les relances envoyées par le job.
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear

    # Act — on exécute le job ET on force la livraison des mails deliver_later
    perform_enqueued_jobs { InactiveUserReminderJob.perform_now }

    # Assert — on regarde les destinataires réellement servis
    destinataires = ActionMailer::Base.deliveries.map { |mail| mail.to.first }

    assert_includes destinataires, "j7@example.com",
                    "Le compte J+7 sans histoire doit être relancé"
    assert_includes destinataires, "j30@example.com",
                    "Le compte J+30 sans histoire doit être relancé"
    assert_not_includes destinataires, "j7actif@example.com",
                        "Un compte qui a déjà une histoire ne doit PAS être relancé"
    assert_not_includes destinataires, "hors@example.com",
                        "Un compte hors des fenêtres J+7/J+30 ne doit PAS être relancé"
  end
end
