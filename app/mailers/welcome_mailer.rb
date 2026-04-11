# app/mailers/welcome_mailer.rb
# Mailer d'accueil — envoyé automatiquement après inscription d'un nouvel utilisateur
# Déclenché depuis le callback after_create_commit dans le modèle User
class WelcomeMailer < ApplicationMailer

  # Email de bienvenue — présente l'app et invite à créer un premier héros
  # @param user [User] — le nouvel utilisateur inscrit
  def welcome_email(user)
    @user       = user
    @first_name = user.first_name
    # URL vers la création d'un héros — premier pas logique après inscription
    @hero_url   = new_child_url(host: "noctilio-app.fr")
    # URL vers le dashboard
    @dashboard_url = dashboard_url(host: "noctilio-app.fr")

    mail(
      to:      user.email,
      subject: "Bienvenue sur Noctilio ✦ #{@first_name} !"
    )
  end
end
