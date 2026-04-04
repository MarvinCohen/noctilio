class PagesController < ApplicationController
  # La page d'accueil est publique — pas besoin d'être connecté
  skip_before_action :authenticate_user!, only: [:home]

  # Utilise le layout "landing" — pas de sidebar ni de navbar Rails
  # La landing page a son propre design autonome
  layout "landing", only: [:home]

  def home
    # Si l'utilisateur est déjà connecté, on le redirige directement
    # vers son dashboard — pas besoin de lui montrer la landing page
    redirect_to dashboard_path if user_signed_in?

    # Cumul : emails waitlist + utilisateurs Devise réellement inscrits
    # Les deux populations représentent l'intérêt total pour Noctilio
    @waitlist_count = WaitlistEntry.count + User.count
  end
end
