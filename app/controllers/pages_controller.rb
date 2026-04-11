class PagesController < ApplicationController
  # Pages publiques — pas besoin d'être connecté
  skip_before_action :authenticate_user!, only: [:home, :cgu, :privacy]

  # Layout landing pour la home, layout application pour les pages légales
  layout "landing", only: [:home]

  # Page CGU — conditions générales d'utilisation
  def cgu; end

  # Page politique de confidentialité
  def privacy; end

  def home
    # Si l'utilisateur est déjà connecté, on le redirige directement
    # vers son dashboard — pas besoin de lui montrer la landing page
    redirect_to dashboard_path if user_signed_in?

    # Cumul : emails waitlist + utilisateurs Devise réellement inscrits
    # Les deux populations représentent l'intérêt total pour Noctilio
    @waitlist_count = WaitlistEntry.count + User.count

    # Phase lunaire du jour — passée au canvas JS pour dessiner la vraie forme
    # La méthode current_moon_phase est définie dans ApplicationController
    @moon_phase = current_moon_phase
  end
end
