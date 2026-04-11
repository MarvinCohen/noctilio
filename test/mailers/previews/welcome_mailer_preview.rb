# test/mailers/previews/welcome_mailer_preview.rb
# Preview accessible en local via : http://localhost:3000/rails/mailers/welcome_mailer/welcome_email
class WelcomeMailerPreview < ActionMailer::Preview

  # Simule l'envoi avec le premier utilisateur en base
  def welcome_email
    user = User.first
    WelcomeMailer.welcome_email(user)
  end
end
