# app/mailers/user_mailer.rb
# ============================================================
# UserMailer — emails de cycle de vie liés au COMPTE utilisateur
# ============================================================
# Contient pour l'instant les relances des comptes inactifs : un parent
# s'inscrit mais ne crée jamais sa première histoire. On lui envoie une
# relance douce à J+7 puis à J+30 pour l'inviter à passer à l'acte.
# Déclenché par InactiveUserReminderJob (job récurrent quotidien).
class UserMailer < ApplicationMailer
  # Relance d'un compte qui n'a encore créé AUCUNE histoire.
  # @param user  [User]    — le destinataire de la relance
  # @param stage [Integer] — l'étape de relance : 7 (J+7) ou 30 (J+30).
  #   Le template adapte son message selon cette valeur (ton plus insistant à J+30).
  def no_story_reminder(user, stage)
    @user       = user
    @first_name = user.first_name
    # Étape de relance, exposée à la vue pour brancher le texte (7 ou 30).
    @stage      = stage

    # Lien direct vers la création d'un héros (premier pas concret vers une histoire).
    # host explicite : dans un mailer il n'y a pas de requête HTTP, donc pas de host déduit.
    @hero_url = new_child_url(host: "www.noctilio-app.fr")

    # Objet adapté à l'étape : plus chaleureux à J+7, plus incitatif à J+30.
    subject = if stage == 30
      "Ton enfant attend toujours sa première histoire ✦"
    else
      "#{@first_name}, et si ce soir tu créais sa première histoire ? ✦"
    end

    mail(to: user.email, subject: subject)
  end
end
